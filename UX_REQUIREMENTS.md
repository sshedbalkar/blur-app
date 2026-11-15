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
  - `method` "Method"; `sharpen` | `focus` | `motion`; default `sharpen`.
  - `radius` "Blur size (px)"; 0.5-50; 0.5; 3. Sharpen: softness radius. Focus: blur disk radius. Motion: smear length.
  - `angle` "Motion angle (°)"; 0-180; 1; 0. 0 = horizontal, 90 = vertical. Motion only.
  - `strength` "Strength"; 0-100; 1; 50. Higher = more detail, more noise/halos.
- Method use: `sharpen` mild softness or unknown cause (safest); `focus` out-of-focus; `motion` straight-line camera shake / subject movement. `neural`: Planned (D-10).
- Method chosen by AI from request or by user. App does not analyse image to choose.
- User supplies blur size/angle; no automatic estimation.
- 8/16-bit images; transparency preserved. Output format = output file extension.
- Errors shown: "Cannot read image: <path>", "Cannot write image: <path>", "Only 8-bit and 16-bit images are supported", "Image processing failed: <detail>" (e.g. unknown output extension).
- Status: Partial. Classical done; neural, video Planned.

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
- Step fails -> "<feature name> failed: <error>", stop. Success -> "Done. Saved to <path>".
- UI stays responsive during run.

### Settings
Scrolling column. App bar title "Settings", back returns to Home (Home reflects changes). Top to bottom:
1. Heading "Logs": field "Log folder".
2. Heading "AI model": switch "Use AI to suggest steps and settings"; field "Local AI server address" (helper: "Any OpenAI-compatible server, e.g. Ollama, llama.cpp, LM Studio"); row: field "Model" + button "Find models". AI fields disabled when switch off.
3. Find models -> selectable chips, one per model; pick fills Model. Messages: "Found <n> model(s). Pick one below." / "The server is reachable but has no models." / error.
4. Buttons "Save", "Restore defaults".
5. Message line; errors in error colour.

Behaviour:
- Edits apply only on Save. Save validates: log folder + address non-empty else "Log folder and AI server address cannot be empty."; address valid URL else "AI server address is not a valid URL." Success "Saved."; logging switches to new folder immediately.
- Restore defaults fills fields only: "Defaults restored. Press Save to keep them."

## Gaps
- Input/output = typed paths. No file picker.
- Param rows always show all params (e.g. angle visible for non-motion methods).
