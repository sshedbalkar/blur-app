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
- Status: Done.

## UX-6: Remove blur (still images)
- Feature id `deblur`, name "Remove blur".
- Params (label; range; step; default):
  - `method` "Method"; `sharpen` | `focus` | `motion` | `neural`; default `sharpen`.
  - `radius` "Blur size (px)"; 0.5-50; 0.5; 3. Sharpen: softness radius. Focus: blur disk radius. Motion: smear length.
  - `angle` "Motion angle (°)"; 0-180; 1; 0. 0 = horizontal, 90 = vertical. Motion only.
  - `strength` "Strength"; 0-100; 1; 50. Higher = more detail, more noise/halos.
- Method use: `sharpen` mild softness or unknown cause (safest); `focus` out-of-focus; `motion` straight-line camera shake / subject movement; `neural` heavy or irregular real-world blur, size/direction unknown (slower).
- `neural`: runs model from UX-7. Ignores `radius`, `angle`, `strength`. Any image size.
  - Uses NVIDIA GPU when usable; else processor, automatically. Processor run adds note after "Done" line: "The neural model ran on the processor, which is much slower, because <reason>." Reasons: "cuDNN 9 is not installed" | "no usable NVIDIA GPU or CUDA 13 runtime was found" | "the GPU ran out of memory" | first line of engine error.
  - Speed, RTX 4070 8 GB: 0.3 MP ~3 s, 12.8 MP ~47 s. Processor: 0.3 MP ~13 s.
  - Errors: UX-7 model errors; "Cannot read model: <path>"; "The neural model failed: <detail>" (not a usable model).
- Method chosen by AI from request or by user. App does not analyse image to choose.
- User supplies blur size/angle; no automatic estimation.
- 8/16-bit images; transparency preserved. Output format = output file extension.
- Errors shown: "Cannot read image: <path>", "Cannot write image: <path>", "Only 8-bit and 16-bit images are supported", "Image processing failed: <detail>" (e.g. unknown output extension).
- Status: Partial. Classical + neural done; video Planned.

## UX-7: Neural models
- One local folder holds models (`.onnx`); default TR-6. Settings: folder, model choice, download.
- App recommends one model per task with reason, shown in Settings: "Recommended for removing blur: NAFNet (92 MB). It removes camera-shake and motion blur without being told the blur size or direction, is a small download, and fits on an 8 GB graphics card."
- "Download recommended model" fetches it into folder; nothing downloaded without that press.
- User adds own: copy `.onnx` into folder. Must meet model contract (TR-9).
- Model used by `neural`: "Neural model" setting if set; else recommended model if in folder; else first in folder by name. Choice remembered (saved setting).
- Errors: "No neural model is installed. Download one in Settings."; "Neural model "<name>" was not found in <folder>. Choose another in Settings."
- Status: Done.

## Screens

App title "Blur App". Material design, indigo seed colour, light + dark themes following system. Two screens: Home, Settings.

### Home
Single scrolling column, 16 px padding. App bar: title, gear icon (tooltip "Settings") -> Settings. Top to bottom:
1. Text field "Input file" (hint `/path/to/file`).
2. Text field "Save result as" (hint `/path/to/result`).
3. If AI on: multi-line field "Describe what you want" (2-4 lines); button "Suggest steps" (sparkle icon), disabled while busy or no features.
4. Row: heading "Steps"; "+" menu (tooltip "Add a step") listing feature names, hidden when no features. Pick -> step appended with default params.
5. Empty states: no features -> "No features are installed yet."; no steps -> "Describe what you want above, or add a step with +." (AI off: "Add a step with +.").
6. Planner notes, small text, one per line.
7. Step cards in order: title "<n>. <feature name>", close icon (tooltip "Remove step"), then one row per param: label (160 px), control. Hover shows param help.
8. Button "Run" (play icon), disabled while busy or no steps.
9. Status line; errors in theme error colour.

Param controls:
- number -> slider min..max, snapping to step, + current value text (0 decimals if whole, else 2).
- boolean -> switch.
- choice -> dropdown.
- All disabled while busy.

Suggest steps flow:
- Empty request -> error "Describe what you want to do first."
- Status "Asking the AI model…"; on reply, steps replaced by plan; notes shown.
- Status after: steps found -> "Review the suggested steps and settings, then run."; none -> "The AI found no matching feature for that request."
- Failure -> error message shown (server unreachable, no model selected, unintelligible reply).
- Notes: "Skipped unknown feature "<id>"."; "<feature>: ignored unknown setting "<id>"."; "<feature>: "<param>" suggested as <v>, adjusted to <v2> to stay in the supported range."

Run flow:
- Checks, in order: input exists else "Input file not found: "<path>""; output non-empty else "Enter where to save the result."; output != input else "Output must be a different file from the input."
- Steps run in order as chain (D-5). Status "Running <feature name>…" per step.
- Step fails -> "<feature name> failed: <error>", stop. Success -> "Done. Saved to <path>", then one line per step note (TR-1) in step order.
- UI stays responsive during run.

### Settings
Scrolling column. App bar title "Settings", back returns to Home (Home reflects changes). Top to bottom:
1. Heading "Logs": field "Log folder".
2. Heading "AI model": switch "Use AI to suggest steps and settings"; field "Local AI server address" (helper: "Any OpenAI-compatible server, e.g. Ollama, llama.cpp, LM Studio"); row: field "Model" + button "Find models". AI fields disabled when switch off.
3. Find models -> selectable chips, one per model; pick fills Model. Messages: "Found <n> model(s). Pick one below." / "The server is reachable but has no models." / error.
4. Heading "Neural blur removal": field "Model folder" (helper: "Put your own .onnx models here to use them"); row: field "Neural model" (helper: "Leave empty to choose automatically") + button "List models"; chips (below); recommendation text (UX-7), small; button "Download recommended model" (download icon).
5. List models -> chips, one per `.onnx` in the typed folder; pick fills Neural model. Messages: "Found <n> model(s) in the folder. Pick one below." / "No models in that folder yet."
6. Download recommended model, into the typed folder:
   - Already there -> "NAFNet is already installed."; chips refreshed.
   - Else "Downloading NAFNet… <n>%" (buttons List models, Find models, Download disabled), then "Downloaded NAFNet. Press Save to keep it selected."; chips refreshed; Neural model filled.
   - Failure: "Could not download NAFNet: the server answered <status>." / "The downloaded NAFNet file is damaged or not the expected version. Try again." / "Could not download NAFNet (<error>)". No partial file left.
7. Buttons "Save", "Restore defaults".
8. Message line; errors in error colour.

Behaviour:
- Edits apply only on Save. Save validates: log folder + address non-empty else "Log folder and AI server address cannot be empty."; address valid URL else "AI server address is not a valid URL." Model folder non-empty else "Model folder cannot be empty." Success "Saved."; logging switches to new folder immediately.
- Restore defaults fills fields only: "Defaults restored. Press Save to keep them."

## Gaps
- Input/output = typed paths. No file picker.
- Param rows always show all params (e.g. angle visible for non-motion methods; all three numbers for `neural`).
- No progress during a run; model download not cancellable.
