# Cereaper — demo & submission runbook

Everything you need to record the 60s demo and submit. The app and the QA flow
are already working end-to-end.

## Headline numbers (captured 2026-06-29)

Cerebras `gemma-4-31b`, full 11-step QA hero flow:

```
Cerebras: steps=11 wall=9.34s avgTTFT=20ms avgTps=1526 tok/s outTokens=899
```

Peak ~2000 tok/s, TTFT as low as 12ms. Use these in the video overlay and the X post.

## Pre-flight (once)

```sh
export CEREBRAS_API_KEY=...
swift run Cereaper
```

- Grant **Accessibility**: System Settings → Privacy & Security → Accessibility → enable Cereaper.
- Grant **Screen Recording** (same pane) so `screenshot` works.
- Hit **Permissions** in the toolbar → status dots should both turn green.

## 60s demo recording script

Screen-record with Cmd+Shift+5 (or OBS). Keep it ≤60s. Suggested beat sheet:

1. **0–5s** — Cereaper window on screen. Status bar: `ready`.
2. **5–8s** — Click **QA demo** in the toolbar (fills the task). Click **Run**.
3. **8–50s** — Watch the **Steps table** fill row by row:
   `bash → write → bash → bash → computer_focus → computer_state → computer_set_value → computer_click → screenshot → image_look → final_answer`.
   The **status bar** ticks live tok/s (you'll see 800–2800 tok/s) and wall clock.
4. **~40s** — The **screenshot inspector** populates with the QA target app window.
5. **~50s** — The **final answer** panel fills with the bug report:
   *"Bug found: label shows 'Hello, world!' instead of 'Hello, Ada!' — the app ignores the text field."*
6. **55–60s** — Hold on the final answer + status bar (avg tok/s, 9.3s total).

Tips: no notifications/other tabs visible; close other apps; turn on Do Not Disturb.
If the live run flakes, play a pre-recording — but it's been reliable across runs.

## Post the video on X (required for all tracks; judged for Track 2)

Post the 60s video with something like:

> Cereaper — a native macOS agent that builds an app, drives it via grounded
> accessibility, and verifies the UI with Gemma 4 vision. 11-step build→run→
> drive→verify→report loop in 9.3s at ~1500 tok/s (peak 2000) on @Cerebras.
> #Gemma4 @googlegemma @Cerebras

Tag **@Cerebras** and **@googlegemma**. No paid promotion (Track 2 is organic).

## Discord submission

Post in **`#g4hackathon-multiverse-agents`** (Track 1, primary). Use this template:

```
Project Name: Cereaper
Team Members: @infatoshi
Project Description: Cereaper is a native macOS desktop agent that autonomously
QA-tests software. It builds a small app, launches it, drives it via grounded
accessibility (AX) actions — focus, read the AX tree, set values, click by real
element index — then captures a screenshot and uses Gemma 4 31B multimodal vision
to verify the UI against intent, reporting grounded bugs. The full 11-step
build→run→drive→verify→report loop runs in ~9s at ~1500 tok/s (peak ~2000) on
Cerebras inference. Multi-agent is the actor + visual-verifier pair; embodied via
native AX on a real OS.
GitHub Repository: https://github.com/Infatoshi/cereaper
Demo Video: (Attached)
```

If also submitting **Track 3 (Enterprise Impact)**, make a separate post in
**`#g4hackathon-enterprise-impact`** with the same video and this description:

```
Project Name: Cereaper
Team Members: @infatoshi
Project Description: Cereaper is an enterprise-ready desktop QA automation agent.
It builds, launches, and drives native macOS apps via the Accessibility API
(grounded targets, fail-closed, confirmation gates), then verifies UI state with
Gemma 4 31B multimodal vision on Cerebras. It catches a real UI bug end-to-end in
~9s at ~1500 tok/s. Production posture: strict tool-call outputs, hard step budget,
final_answer termination, no coordinate guessing. Target: automated UI regression
testing / multimodal RPA.
GitHub Repository: https://github.com/Infatoshi/cereaper
Demo Video: (Attached)
```

Deadline: **Mon Jun 29, 10:00 AM PT**. You can resubmit/update any time before then.

## Verify before submitting

```sh
swift build          # builds clean
swift run Cereaper --smoke    # 3-step smoke: screenshot + image_look + final_answer
swift run Cereaper --qa       # full 11-step QA hero flow
swift run Cereaper --race     # Cerebras telemetry summary
```
