import Foundation
import AppKit
import CoreGraphics

/// A tool the agent can call. Each tool owns its spec schema and its execution.
protocol Tool {
    var name: String { get }
    var spec: ToolSpec { get }
    func run(argumentsJSON: String) async throws -> String
}

/// Registry that produces the OpenAI tool definitions and dispatches calls.
final class ToolRegistry {
    private(set) var tools: [String: Tool] = [:]

    func register(_ tool: Tool) { tools[tool.name] = tool }

    var specs: [ToolSpec] { Array(tools.values.map { $0.spec }) }

    func run(_ call: ToolCall) async -> String {
        guard let tool = tools[call.name] else {
            return "error: unknown tool '\(call.name)'"
        }
        do {
            return try await tool.run(argumentsJSON: call.argumentsJSON)
        } catch {
            return "error: \(error)"
        }
    }
}

// MARK: - read

final class ReadTool: Tool {
    let name = "read"
    let spec = ToolSpec(type: "function", function: .init(
        name: "read",
        description: "Read a UTF-8 text file at an absolute path. Returns the file contents.",
        parameters: .object([
            (name: "path", schema: .string(description: "Absolute file path"), required: true),
        ])
    ))
    func run(argumentsJSON: String) async throws -> String {
        let path = try Self.stringArg("path", from: argumentsJSON)
        return try String(contentsOfFile: path, encoding: .utf8)
    }
}

// MARK: - bash

final class BashTool: Tool {
    let name = "bash"
    let spec = ToolSpec(type: "function", function: .init(
        name: "bash",
        description: "Run a shell command (zsh -c). Returns combined stdout+stderr and the exit code.",
        parameters: .object([
            (name: "command", schema: .string(description: "Shell command to run"), required: true),
        ])
    ))
    func run(argumentsJSON: String) async throws -> String {
        let command = try Self.stringArg("command", from: argumentsJSON)
        let proc = Process()
        proc.launchPath = "/bin/zsh"
        proc.arguments = ["-c", command]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        try proc.run()
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: data, encoding: .utf8) ?? ""
        return "exit=\(proc.terminationStatus)\n\(out)"
    }
}

// MARK: - write

final class WriteTool: Tool {
    let name = "write"
    let spec = ToolSpec(type: "function", function: .init(
        name: "write",
        description: "Write text to a file at an absolute path, creating or overwriting it.",
        parameters: .object([
            (name: "path", schema: .string(description: "Absolute file path"), required: true),
            (name: "content", schema: .string(description: "File contents"), required: true),
        ])
    ))
    func run(argumentsJSON: String) async throws -> String {
        let path = try Self.stringArg("path", from: argumentsJSON)
        let content = try Self.stringArg("content", from: argumentsJSON)
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        return "wrote \(content.count) bytes to \(path)"
    }
}

// MARK: - screenshot

final class ScreenshotTool: Tool {
    let name = "screenshot"
    let spec = ToolSpec(type: "function", function: .init(
        name: "screenshot",
        description: "Capture the main screen to a PNG and return the absolute path.",
        parameters: .object([])
    ))
    func run(argumentsJSON: String) async throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cereaper-\(UUID().uuidString).png")
        try Self.captureScreen(to: url)
        return url.path
    }

    static func captureScreen(to url: URL) throws {
        let displayID = CGMainDisplayID()
        guard let image = CGWindowListCreateImage(
            .infinite,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.nominalResolution]
        ) else {
            throw NSError(domain: "screenshot", code: 1, userInfo: [NSLocalizedDescriptionKey: "capture failed"])
        }
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
        guard let dest else { throw NSError(domain: "screenshot", code: 2, userInfo: nil) }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "screenshot", code: 3, userInfo: nil)
        }
    }
}

// MARK: - image_look (multimodal verify via Cerebras Gemma 4)

final class ImageLookTool: Tool {
    let name = "image_look"
    let spec = ToolSpec(type: "function", function: .init(
        name: "image_look",
        description: "Look at an image file and answer a question about it using Gemma 4 vision. Use to verify screenshots of UI state.",
        parameters: .object([
            (name: "path", schema: .string(description: "Absolute path to a PNG/JPEG/WebP"), required: true),
            (name: "question", schema: .string(description: "Question about the image"), required: true),
        ])
    ))
    let client: CerebrasClient
    init(client: CerebrasClient) { self.client = client }

    func run(argumentsJSON: String) async throws -> String {
        let path = try Self.stringArg("path", from: argumentsJSON)
        let question = try Self.stringArg("question", from: argumentsJSON)
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let mime = path.lowercased().hasSuffix(".jpg") || path.lowercased().hasSuffix(".jpeg")
            ? "image/jpeg" : "image/png"
        let uri = "data:\(mime);base64,\(data.base64EncodedString())"
        let result = try await client.complete(
            messages: [
                .system("You inspect screenshots. Answer the question concisely and factually. If you cannot tell, say so."),
                .user([.text(question), .image(dataURI: uri)]),
            ],
            reasoningEffort: "high",
            temperature: 0,
            maxTokens: 512
        )
        return result.text
    }
}

// MARK: - final_answer (spec only; the Agent loop intercepts the call before dispatch)

final class FinalAnswerTool: Tool {
    let name = "final_answer"
    let spec = ToolSpec(type: "function", function: .init(
        name: "final_answer",
        description: "Call this exactly once when the task is complete. The argument is the final summary to show the user (include any bugs found).",
        parameters: .object([
            (name: "summary", schema: .string(description: "Final summary of what was done and any bugs found"), required: true),
        ])
    ))
    func run(argumentsJSON: String) async throws -> String { "ok" }
}

// MARK: - arg parsing helpers

extension Tool {
    static func stringArg(_ key: String, from json: String) throws -> String {
        guard let data = json.data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let val = obj[key] as? String else {
            throw ToolError.missingArg(key)
        }
        return val
    }
}

enum ToolError: Error {
    case missingArg(String)
}
