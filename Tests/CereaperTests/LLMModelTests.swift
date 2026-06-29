import XCTest
@testable import Cereaper

final class LLMModelTests: XCTestCase {
    func testTextContentBlockRoundTrip() throws {
        let block = ContentBlock.text("hello")
        XCTAssertEqual(block.kind, .text)
        XCTAssertEqual(block.text, "hello")
    }

    func testImageContentBlock() {
        let block = ContentBlock.image(dataURI: "data:image/png;base64,AAAA")
        XCTAssertEqual(block.kind, .image_url)
        XCTAssertEqual(block.imageURI, "data:image/png;base64,AAAA")
    }
}
