# Technical requirements

Each names need served (TR-3). Code locations: `context/ROUTING.md`.

## Architecture
- Flutter app, single process. Layers: UI (screens) -> core (feature contract, registry, AI planner, logger, settings) -> features (Dart classes) -> native engine (C++ shared lib via FFI).
- Startup: load settings -> create logger at settings' log dir -> create registry -> register built-in features -> log `app_start` -> show Home. These four objects passed to screens as one services object.
- Dependencies: `material_ui`, `http`, `ffi`; dev `flutter_test`, `flutter_lints`. System: GTK3, OpenCV 4.
- Tests: unit (core), widget (screens with fake feature), deblur (real native lib on synthetic images: blur with known kernel, assert error vs original drops).

## TR-1: Feature interface
- `Feature`: `id` (stable, used in commands/logs/AI), `name`, `description` (plain language; AI matches requests on it), `params` (list of `ParamSpec`), `run(context, params) -> Future<FeatureResult>`.
- `ParamSpec` (sealed): `id`, `label`, `help`, `defaultValue`, `coerce(raw)`, `describe()` (JSON for AI). Kinds:
  - `NumParam`: `min`, `max`, optional `step`. Coerce: number or numeric string clamped to range; else default. Describe: `{id, type:"number", min, max, default, help?}`.
  - `BoolParam`. Coerce: bool, or "true"/"false"; else default. Describe type `"boolean"`.
  - `ChoiceParam`: `options`. Coerce: string in options; else default. Describe type `"choice"` + `options`.
- `FeatureContext`: `inputPath`, `outputPath`. `FeatureResult`: ok(`outputPath`) | failed(`error` message).
- `FeatureCommand(feature, rawParams)`: one planned run. Missing params -> defaults; supplied -> coerced; unknown keys dropped. `set(paramId, value)` coerces. `run` passes read-only params. `toJson` = `{feature, params}`.
- Values coerced before run, any source (UI, AI, code).
- Registry: `register` (rejects duplicate feature id, duplicate param id), `unregister`, `byId`, `all`, change listeners. Usable at runtime; Home listens and drops steps of removed features.
- Built-in features registered in one function, called at startup.
- Serves: UX-1, UX-2, UX-3.

## TR-2: Persistent local logs
- Logged to file: every user interaction, every user input, every non-trivial app decision, plus normal diagnostics. Each line also echoed to stdout.
- File: `blur-app_YYYY-MM-DD.log`, one per day, append, flushed per line. Creation time in name optional; unused.
- Format: JSON object per line: `time` (ISO 8601 local), `kind` (`interaction`|`input`|`decision`|`info`|`error`), `event`, `data` (omitted if empty).
- Default dir: `$XDG_STATE_HOME/blur-app/logs` (fallback `~/.local/state`). User-changeable in Settings; old files stay.
- Log failure never stops app: message to stderr, continue.
- Events:
  - info: `app_start` {features, logFile}; `command_start` {feature, params}; `command_done` {feature, output}.
  - interaction: `plan_pressed`; `run_pressed`; `command_added` {feature}; `command_removed` {feature}; `settings_opened`; `find_models_pressed` {baseUrl}; `ai_toggle` {enabled}; `model_picked` {model}; `settings_reset_pressed`.
  - input: `request` {text}; `paths` {input, output}; `param_changed` {feature, param, value} (on release, not per drag tick); `settings_saved` {before, after}.
  - decision: `plan` {request, modelReply, commands, notes}.
  - error: `plan_failed`; `command_failed` {feature, error}; `run_crashed`; `find_models_failed`; `settings_save_failed`.
- Serves: debugging.

## TR-3: Nothing without purpose
- Every requirement and piece of code serves UX requirement, product requirement, debugging, or optimization. Not needed in current end-user context -> not in live version.

## TR-4: Front-end stack
- Flutter (Dart), Linux desktop, Material. Why: D-1.
- Complicated/performance-critical feature work -> native via `dart:ffi`. Rest in Dart.
- Native engine: C++17 + OpenCV (core, imgproc, imgcodecs; system package), one shared lib `libblur_native.so`, built by own CMake project, pulled into app build, bundled in app `lib/`.
- Lib lookup: `<executable dir>/lib/libblur_native.so`; if absent `build/native/libblur_native.so` (tests).
- Native API style: one exported C function per operation; returns 0 ok / non-zero + message in caller buffer (512 bytes); C++ exceptions caught inside.
- Native calls run on background isolate; UI never blocked.
- Serves: all UX; dev speed.

## TR-5: Security
- Not required while app is front-end only and local. Revisit on remote input or non-local services.

## TR-6: Central global settings
- All global settings defined in one file, machine-suited defaults, one Settings screen, user-changeable.
- Stored: `$XDG_CONFIG_HOME/blur-app/settings.json` (fallback `~/.config`), pretty JSON. Written only on Save.
- Keys, defaults: `logDirectory` (TR-2 default); `aiEnabled` true; `aiBaseUrl` `http://localhost:11434/v1`; `aiModel` "" (none chosen).
- Missing/damaged file -> defaults. Missing/mistyped key -> that key's default.
- Serves: UX-5.

## TR-7: Local AI access
- OpenAI-compatible HTTP API on local server. Address + model = settings. No auth. Timeout 120 s.
- `GET {base}/models` -> `data[].id` = model names.
- `POST {base}/chat/completions` body `{model, temperature: 0, messages: [system, user]}` -> `choices[0].message.content`.
- Errors -> user-readable message: unreachable server, non-200 (status + body), non-JSON, no reply, no model selected ("No AI model selected. Choose one in Settings.").
- Planner system prompt: task statement; JSON list of features `{id, description, params: [describe()]}`; instruction to choose values within min/max/options; reply JSON only, shape `{"commands":[{"feature":"<id>","params":{"<param id>":<value>}}]}`; only listed ids; nothing fits -> `{"commands":[]}`. User message = request text.
- Reply parsing: take text from first `{` to last `}` (tolerates code fences/prose); needs `commands` list else error "The AI reply could not be understood: <reply>". Per command: unknown feature -> skip + note; build `FeatureCommand` (coerces); unknown param -> note; value changed by coercion -> note.
- No features registered -> error, no model call.
- Model only proposes. App validates against registry + param ranges.
- Serves: UX-1, UX-3, UX-4.

## TR-8: Deblur engine
- C function `blur_deblur(input_path, output_path, method, radius, angle_deg, strength, err, err_len) -> int`. `method`: 0 sharpen, 1 focus, 2 motion (order = feature's method option order).
- Rejects: unknown method; radius <= 0; strength outside 0-100.
- Pipeline: read unchanged (keeps depth + alpha) -> require 8- or 16-bit -> set alpha aside -> float 0..1 -> method -> saturate back to original depth -> re-attach alpha -> write (format by extension).
- sharpen: unsharp mask. `out = src*(1+a) - gaussian(src, sigma=radius)*a`, `a = strength/50`.
- focus kernel: disk radius r, soft edge: weight `clamp(r + 0.5 - distance, 0, 1)`, normalised.
- motion kernel: line length L at angle (0 = horizontal, counter-clockwise), one pixel wide: sample 16 points per px along line, each credited to nearest pixel, normalised. Whole-pixel axis-aligned L = exact box.
- focus/motion: Wiener deconvolution per colour channel (channels in parallel), frequency domain: `F = G·conj(H)·(1+nsr) / (|H|² + nsr)`, `nsr = 10^(-1 - 3·strength/100)`.
  - Pad each side `max(3·kernel size, 32)` px, mirrored, total rounded up to fast FFT size; padding faded to channel mean with raised-cosine window; kernel placed centred on origin with wrap-around; crop after.
- Reasons for padding fade, (1+nsr), line width: D-9.
- Serves: UX-6.
