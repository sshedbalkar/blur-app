# UX requirements

Status values: Done (works, tested) | Partial (see note) | Planned. Update on behaviour change.

## UX-1: Describe what you want
- Plain-language request -> AI -> ordered list of feature steps.
- Nothing runs until user presses Run.
- Steps removable; addable by hand without AI.
- AI asks for unknown feature -> step dropped, user told.
- Status: Done. Untested against real model server.

## UX-2: Plug-and-play features (optional)
- Add feature without changing rest of app. Runtime add = nice-to-have.
- Status: Partial. Feature = one class + one registration line; UI updates live on registry change. External runtime loading not built (D-4).

## UX-3: AI-suggested params, user-adjustable
- AI suggests best params per step. Every param shown in UI, editable.
- All values within feature's supported range. Controls cannot exceed it. Out-of-range AI value -> coerced, user told.
- Status: Done.

## UX-4: Plug in local AI model
- Settings: server address, model name. "Find models" lists server's models.
- AI can be off -> hand-added steps only.
- Status: Done. Any OpenAI-compatible server (Ollama, llama.cpp server, LM Studio).

## UX-5: Central settings
- Every global setting on Settings screen; machine-suited default; changeable; restorable.
- Current: log folder, AI on/off, AI server address, model.
- Status: Done.

## UX-6: Remove blur (still images)
- Feature `deblur`. Params: method, blur size 0.5-50 px, motion angle 0-180 deg (motion only), strength 0-100.
- Methods: `sharpen` (default; mild/unknown blur), `focus` (out-of-focus), `motion` (straight-line smear). `neural`: Planned.
- Method chosen by AI from request or by user. App does not analyse image to choose.
- User supplies blur size/angle; no automatic estimation.
- 8/16-bit images; transparency preserved. Output format = output file extension.
- Status: Partial. Classical done; neural, video Planned.

## Gaps
- Input/output = typed paths. No file picker.
