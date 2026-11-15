# Routing map (root)

Pointers only; source = truth. Update on any structure change.

Stack: Flutter 3.50 / Dart 3.14, Linux desktop, `material_ui`, `http`, `ffi`, `crypto`. Native: C++17 + OpenCV 4 + ONNX Runtime 1.32 (CUDA 13). Package name `blur_app`.

## Docs
- rules, validation, report format, `.md` writing style -> AGENTS.md
- user-facing behaviour, screens, messages, status -> UX_REQUIREMENTS.md (UX-n)
- architecture, interfaces, formats, algorithms -> TECHNICAL_REQUIREMENTS.md (TR-n)
- decisions -> DESIGN.md (D-n)

## Source
- entry, `AppServices` (settings, logger, registry), theme -> lib/main.dart
- feature contract: `Feature`, `ParamSpec` (`NumParam`/`BoolParam`/`ChoiceParam`), `FeatureCommand`, `FeatureContext`, `FeatureResult` -> lib/core/feature/feature.dart
- registry (register/unregister/listeners) -> lib/core/feature/feature_registry.dart
- feature registration point -> lib/features/builtin.dart
- deblur feature: params, method list, classical + neural isolate calls, CPU note -> lib/features/deblur/deblur_feature.dart
- deblur FFI bindings (`deblurNative`, `neuralDeblurNative`), native lib path lookup -> lib/features/deblur/deblur_native.dart
- neural models: recommended model, list, choice, download -> lib/features/deblur/neural_models.dart
- native engine: `blur_deblur` (sharpen, kernels, Wiener), `blur_neural_deblur` (ONNX Runtime session, tiling, GPU->CPU fallback), shared file pipeline -> native/blur_native.cpp
- native build, ONNX Runtime fetch + bundling -> native/CMakeLists.txt; pulled into app build by linux/CMakeLists.txt
- file logging, `LogKind` -> lib/core/logging/app_logger.dart
- global settings, defaults, load/save -> lib/core/settings/app_settings.dart
- HTTP to local model (`/models`, `/chat/completions`) -> lib/core/ai/ai_client.dart
- request -> commands, prompt, reply parsing, range notes -> lib/core/ai/command_planner.dart
- main workflow screen (plan, edit steps, run chain), `stepTempPath` -> lib/ui/home_screen.dart
- per-param widget -> lib/ui/param_control.dart
- settings screen -> lib/ui/settings_screen.dart
- Linux runner (generated; app id `dev.blurapp.blur_app`) -> linux/

## Tests
- core logic, `FakeFeature` -> test/core_test.dart
- widgets -> test/widget_test.dart
- deblur via real native lib (needs build/native, see AGENTS.md) -> test/deblur_test.dart
- neural via real native lib: identity model, real model (needs build/native + build/models, see AGENTS.md) -> test/neural_deblur_test.dart

## Recipes
- add feature: new folder in lib/features/ implementing `Feature`; register in builtin.dart; add tests; add UX-n entry.
- add global setting: field + default + toJson/load in app_settings.dart; control in settings_screen.dart; list in UX-5.
- log user action: `logger.interaction` / `.input`; app choice: `.decision`.
- native code: add exported C function in native/blur_native.cpp + matching typedefs in a `*_native.dart`; keep signatures in sync by hand; call via `Isolate.run`.

## Runtime paths
- settings: $XDG_CONFIG_HOME/blur-app/settings.json
- logs: $XDG_STATE_HOME/blur-app/logs/blur-app_YYYY-MM-DD.log
- neural models: $XDG_DATA_HOME/blur-app/models/*.onnx
- build deps cache (ONNX Runtime): $XDG_CACHE_HOME/blur-app/deps
