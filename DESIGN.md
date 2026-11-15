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
Step reads previous step's output. Intermediates = temp files beside output, deleted after. Only last step writes user's output path. Input never overwritten.

## D-6: XDG locations
Settings in XDG config dir, logs in XDG state dir.

## D-7: General media toolbox
Scope = general pluggable media processing. Blur removal = first intended feature.
