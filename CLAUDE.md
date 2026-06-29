# Cereaper — project guide for Claude

Read `AGENTS.md` first. It is the durable spec: lineage from `tau`, architecture,
safety posture, Gemma-4 reliability plan, and submission plan.

## TL;DR

Cereaper is a native Swift macOS desktop agent for the Cerebras × Gemma 4
hackathon. It uses **grounded accessibility computer-use** (native AX, not
screenshot-coordinate guessing), powered by **`gemma-4-31b` on Cerebras**, with
**multimodal visual verification** (screenshots → Gemma 4 image input) and a
**Cerebras-vs-GPU race** demo.

Hero demo: agent builds a tiny app → runs it → drives it via AX → screenshots →
multimodal-verifies the UI against intent → reports grounded bugs. 60s video,
side-by-side vs a GPU provider.

## Conventions

- Swift Package, one executable target (`Sources/Cereaper/`). Build with
  `swift build`, run with `swift run`.
- Provider behavior stays in `CerebrasClient`. Canonical message model in
  `LLMModel`. Tool behavior in `Tools`. AX in `ComputerUse`. Loop in `Agent`.
  UI in `App*`.
- `tau-reference/` is inspiration only — gitignored, never linked.
- Fail closed. Never guess coordinates. Confirmation gate on irreversible
  actions. Demo with burner accounts. Always keep a fallback recording.
- Model: `gemma-4-31b`. Reasoning off by default; set `reasoning_effort` only
  when needed. Images: base64 data URIs only.

## Hackathon deadlines

- Submit by **Mon Jun 29, 10:00 AM PT**.
- Post demo on X tagging @Cerebras and @googlegemma.
- Discord channels: `#g4hackathon-multiverse-agents` (Track 1, primary),
  `#g4hackathon-enterprise-impact` (Track 3, secondary).
