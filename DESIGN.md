# Design decisions

Add entry when decision made or reversed. All dated 2026-11-15 unless stated.

## D-1: Flutter UI
Over Tauri, Qt/QML, Electron. Hot reload, `dart:ffi`, Google-backed, large community, stable. Widgets: `material_ui` package.

## D-2: AI via OpenAI-compatible local server
No embedded model. Calls user's local server. Model swap = settings change; no model runtime in app. Default `http://localhost:11434/v1` (Ollama). Cost: user runs server.

## D-3: AI proposes, app decides
Model gets feature list + param ranges, replies JSON commands. App drops unknown features, coerces values, reports changes. Runs only on user Run.

## D-4: Features compiled in, one registration point
Dart class implementing `Feature`, registered in `lib/features/builtin.dart`. Registry supports runtime add/remove; UI reacts. No external plug-in loader: optional (UX-2), deferred until needed. Likely route: shared libs over FFI.

## D-5: Steps run as chain
Step reads previous step's output. Intermediates = temp files beside output, keeping output's extension (features pick format from it), deleted after. Only last step writes user's output path. Input never overwritten.

## D-6: XDG locations
Settings in XDG config dir, logs in XDG state dir.

## D-7: General media toolbox
Scope = general pluggable media processing. Blur removal = first feature.

## D-8: Native engine = C++ on OpenCV via FFI
Chosen for speed + format coverage over self-contained C++. Cost: app depends on system OpenCV. One C function per operation; errors returned as message string, never thrown across FFI.

## D-9: Classical deblur methods
- `sharpen`: unsharp mask. Default: safe when blur cause unknown. Not a true inverse.
- `focus`/`motion`: Wiener deconvolution, known kernel (disk / line). Chosen: fast, one-pass, few params. Blind kernel estimation not attempted.
- Found necessary by test (spec: TR-8): fade padding to mean, else edges ring across image at high strength; (1+nsr) scale, else image darkens up to 9%; line kernel one pixel wide, since anti-aliased 3 px line models sideways blur and fails.
- Kernel mismatch + high strength -> artefacts. Inherent; user lowers strength.

## D-10: Neural deblur (decided, not built)
- ONNX Runtime, GPU (CUDA) from start. Prereq: NVIDIA driver + CUDA on machine.
- Models: app downloads default + user adds own; all in one local folder; switchable; last used remembered.
- App recommends best model(s) per task, with reason message.
- Method stays user/AI-changeable; classical stays default.

## D-11: Core docs = complete spec
Four core docs must suffice to recreate project (AGENTS.md rule 2). Consequence: UX doc carries screen layouts + exact messages; technical doc carries interfaces, formats, algorithms. `context/` stays pointers only.
