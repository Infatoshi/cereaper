# Cereaper

Cereaper is a native macOS desktop agent, built for the **Cerebras × Google DeepMind
Gemma 4 24-Hour Hackathon**. It autonomously performs real desktop tasks using
**grounded accessibility computer-use**, powered by **Gemma 4 31B on Cerebras
inference**, with **multimodal visual verification** and a built-in
**Cerebras-vs-GPU race** demo.

## Lineage: this project vs `tau`

Cereaper is a fresh Swift app *inspired by* `tau` (https://github.com/Infatoshi/tau),
a minimal Rust coding-agent harness by the same author. `tau` is checked out at
`tau-reference/` as **inspiration only — it is not compiled into Cereaper and is
gitignored**. Nothing is linked across the language boundary.

What Cereaper **borrows from `tau` in spirit** (architectural patterns, not code):

- A small, provider-neutral canonical message/content-block model (`tau-llm`).
- A Cerebras Chat Completions adapter that keeps provider oddities at the
  boundary (`tau-providers`).
- **Grounded, fail-closed computer-use**: act on real accessibility targets,
  verify outcomes, fail closed instead of guessing screen coordinates
  (`tau-computer-use`). Cereaper uses the **native macOS Accessibility API**
  (ApplicationServices) directly rather than `tau`'s `osascript` approach.
- A `screenshot` + multimodal `image_look` pair where the screenshot is just a
  PNG on disk and vision is a separate multimodal model call (`tau-tools`).
- An append-only session transcript and a tool trait.

What Cereaper **builds fresh during the hackathon** (the core functionality):

1. The autonomous **desktop-task agent loop** with strict tool-call-only output,
   a hard step budget, and a `final_answer` termination tool.
2. The **visual-verification step**: screenshots fed back through Gemma 4's
   multimodal input to confirm each action's effect.
3. The **QA hero flow**: build a tiny app → run it → drive it via AX →
   screenshot → verify the UI against intent → report grounded bugs.
4. The **race harness**: run the same task on Cerebras and on a GPU provider,
   capture `time_info` telemetry, and produce the side-by-side 60s demo.
5. The **native AppKit product surface** (window, transcript, controls).

This split is the rules-compliance posture: `tau`'s patterns are scaffolding /
boilerplate (explicitly permitted); the core project is built during the 24h and
centers Gemma 4 on Cerebras.

## Project shape

A single Swift Package, one executable target. Keep the layout boring.

- `Sources/Cereaper/LLMModel.swift` — canonical `Message` / `ContentBlock` /
  `ToolCall` / `TimeInfo` / `Usage`. Provider-neutral.
- `Sources/Cereaper/CerebrasClient.swift` — Cerebras Chat Completions adapter
  (OpenAI-compatible), `reasoning_effort`, base64 image input, `time_info`.
- `Sources/Cereaper/Agent.swift` — the agent loop, step budget, fail-closed.
- `Sources/Cereaper/Tools.swift` *(to add)* — tool protocol + `read`, `bash`,
  `write`, `edit`, `screenshot`, `image_look`, `computer_use`.
- `Sources/Cereaper/ComputerUse.swift` *(to add)* — native AX: `focus_app`,
  `get_app_state`, `click`, `type`, `paste`, `press_key`, `set_value`.
- `Sources/Cereaper/QA.swift` *(to add)* — the hero build→run→drive→verify→report flow.
- `Sources/Cereaper/Race.swift` *(to add)* — Cerebras-vs-GPU timing harness.
- `Sources/Cereaper/AppController.swift` / `AppDelegate.swift` / `main.swift` —
  AppKit window, transcript, controls.

## Runtime

- Model ID: `gemma-4-31b` on the standard Cerebras Inference API
  (`https://api.cerebras.ai/v1`). No separate preview endpoint.
- API key: `CEREBRAS_API_KEY` from the environment.
- Reasoning is **off by default**. Set `reasoning_effort` to `low`/`medium`/
  `high` to enable thinking. Use `none` for the action model in the speed race;
  use `high` for the visual-verification step where reasoning helps.
- Image input: **base64 data URIs only** via `image_url` content blocks. No
  hosted image URLs (Cerebras does not accept them yet).
- Hackathon elevated limits (for approved Org IDs): 100 RPM, 100K TPM, 65K MSL /
  32K MCL context. Access window: Sun Jun 28 10:30 AM PT → Mon Jun 29 10:00 AM PT.

## Commands

```sh
swift build
swift run
swift test
```

Run `swift build` before declaring non-trivial changes complete.

## Safety posture (non-negotiable for a live desktop demo)

- **Fail closed.** If an accessibility target is not exposed, stop and report.
  Never guess coordinates, scroll around, or click browser chrome.
- **Irreversible actions get a confirmation gate.** Anything that submits, posts,
  sends, deletes, or files must be confirmed in the UI before execution.
- **Demo with burner accounts.** Use a burner GitHub account and a sandbox
  Slack/Discord workspace. No real credentials or notifications on screen.
- **AX-friendly target apps only.** Safari, Notes, Finder, Terminal, and the
  agent's own generated app. Avoid canvas/WebGL/Electron apps that hide AX.
- **Always have a fallback recording.** Pre-record a clean run; if the live run
  flakes, play the recording. The 60s demo must not die on stage.

## Contribution principles

Make Cereaper easy to extend without making it clever.

- Keep provider behavior in `CerebrasClient`; keep tool behavior in `Tools`;
  keep AX behavior in `ComputerUse`; keep the loop in `Agent`; keep UI in the
  App files. Do not cross these boundaries casually.
- Prefer boring structs and enums over framework-like abstractions.
- Preserve the canonical message model in `LLMModel`. Adapt Cerebras oddities
  into that model instead of leaking provider shapes through the codebase.
- Avoid hidden magic. If Cereaper injects context, reads a file, loads config,
  or enables a tool, the behavior should be discoverable in code.
- Do not add retry loops, fallbacks, or broad compatibility shims until the
  exact failure mode is understood (carried over from `tau`).
- Do not paste giant prompt text into core logic. Keep harness policy in one
  place and dynamic runtime facts structured.

## Gemma-4 reliability note

`tau`'s `AGENTS.md` documents that `gemma-4-31b-trial` leaked visible reasoning
after tool results and was unreliable for interactive agentic use. Cereaper
assumes the hackathon `gemma-4-31b` *may* still do this and defends against it
from day one:

- Strict tool-call-only outputs (structured outputs / strict mode).
- A hard step budget per run.
- A `final_answer` tool that forces termination instead of free text.
- Stop sequences to truncate any leaked reasoning.

If the model turns out to be well-behaved with `reasoning_effort = high`, these
are cheap insurance. If it is not, they are load-bearing.

## Submission plan

- **Track 1 (Multiverse Agents, $2K)** — primary. Multi-agent is the
  actor + visual-verifier pair; multimodal via screenshots; embodied/real-world
  bonus via native AX on a real OS.
- **Track 3 (Enterprise Impact, $1K)** — secondary. Desktop QA automation is
  enterprise RPA-adjacent; emphasize production-readiness + technical excellence.
- **Track 2 (People's Choice, $2K)** — the 60s race video on X, tagging
  @Cerebras and @googlegemma.
- Deadline: **Mon Jun 29, 10:00 AM PT**. Post in
  `#g4hackathon-multiverse-agents` (and `#g4hackathon-enterprise-impact` if
  submitting Track 3), with a separate Discord post per track.
- Demo video: max 60s, show Cerebras speed, recommended side-by-side vs GPU,
  no secrets on screen.
