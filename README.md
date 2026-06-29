# Cereaper

Native macOS desktop agent for the Cerebras × Google DeepMind Gemma 4 hackathon.

Cereaper autonomously performs real desktop tasks via **grounded accessibility
computer-use**, powered by **Gemma 4 31B on Cerebras inference**, with
**multimodal visual verification** and a built-in **Cerebras-vs-GPU race** demo.

## Run

```sh
export CEREBRAS_API_KEY=...
swift run
```

## Hero demo

Agent builds a tiny app → runs it → drives it via AX → screenshots →
multimodal-verifies the UI against intent → reports grounded bugs. 60s video,
side-by-side vs a GPU provider.

## Layout

See `AGENTS.md` for the full spec, lineage from `tau`, safety posture, and
submission plan. `CLAUDE.md` is the short guide. `.cursor/rules/cereaper.mdc`
holds editor conventions.
