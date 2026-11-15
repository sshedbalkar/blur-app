# UX requirements

Status values: Done (works, tested) | Partial (see note) | Planned. Update on behaviour change.

## UX-1: Describe what you want
- Plain-language request -> AI -> ordered list of feature steps.
- Nothing runs until user presses Run.
- Steps removable; addable by hand without AI.
- AI asks for unknown feature -> step dropped, user told.
- Status: Partial. Flow works; no features installed, nothing to plan against.

## UX-2: Plug-and-play features (optional)
- Add feature without changing rest of app. Runtime add = nice-to-have.
- Status: Partial. Feature = one class + one registration line; UI updates live on registry change. External runtime loading not built (D-4).

## UX-3: AI-suggested params, user-adjustable
- AI suggests best params per step. Every param shown in UI, editable.
- All values within feature's supported range. Controls cannot exceed it. Out-of-range AI value -> coerced, user told.
- Status: Done (no real features yet).

## UX-4: Plug in local AI model
- Settings: server address, model name. "Find models" lists server's models.
- AI can be off -> hand-added steps only.
- Status: Done. Any OpenAI-compatible server (Ollama, llama.cpp server, LM Studio).

## UX-5: Central settings
- Every global setting on Settings screen; machine-suited default; changeable; restorable.
- Current: log folder, AI on/off, AI server address, model.
- Status: Done.

## Gaps
- Input/output = typed paths. No file picker.
