# Agent rules

Blur App: local Linux desktop media toolbox, Flutter. Features = plug-ins behind one interface. Local AI model: plain-language request -> feature commands + suggested params.

Start: `context/ROUTING.md`. Source = truth; map only points.

## Rules
1. Clarity >95% before any project/repo change. Lower -> ask.
2. **Major requirement: core docs = complete spec.** Core docs: `AGENTS.md`, `DESIGN.md`, `TECHNICAL_REQUIREMENTS.md`, `UX_REQUIREMENTS.md`.
   - Test: capable model (e.g. Opus 5.5) given only these four files recreates project with all main features, minimal UX loss.
   - Every major change (feature, behaviour, UI, param, default, algorithm, interface, dependency, decision) updates them in same change.
   - Split: `UX_REQUIREMENTS.md` = screens, flows, messages, params, status. `TECHNICAL_REQUIREMENTS.md` = architecture, interfaces, formats, algorithms, constraints + need served. `DESIGN.md` = decisions + why.
   - Docs vs source disagree -> source wins; fix docs.
3. Structure/entry-point/convention change -> update `context/`, same change.
4. Validate every change. End response with validation report.
5. Nothing speculative. Each technical addition serves UX/product requirement, debugging, or optimization (TR-3). Else omit.
6. All `.md` files, repo-wide: written for AI models. Clear, zero redundancy, minimal words, grammar optional, pointers over prose. One fact, one place; elsewhere reference it.

## Validation
From repo root. `flutter` not on PATH -> `~/.local/share/flutter/bin`.

| Change | Run |
| --- | --- |
| Dart code | `dart format lib test`; `flutter analyze`; native build (below); `flutter test` |
| UI behaviour | above + widget test for change |
| Linux runner, native/FFI, deps | above + `flutter build linux`; confirm `build/linux/x64/release/bundle/lib/` has `libblur_native.so`, `libonnxruntime.so.1`, `libonnxruntime_providers_cuda.so` |
| Neural engine | above + `flutter test test/neural_deblur_test.dart` with cuDNN on loader path; printed note must say GPU |
| `.md` only | referenced paths exist; rule 6 |
| Any major change | rule 2 test: changed behaviour recreatable from core docs alone |

Native build (tests load `build/native/libblur_native.so`; first run downloads ONNX Runtime, 234 MB): `cmake -S native -B build/native -G Ninja -DCMAKE_BUILD_TYPE=Release && cmake --build build/native`

Neural test files (tests read `build/models/`; URL base `https://huggingface.co/opencv/deblurring_nafnet/resolve/f1f255116cdb628a311d2b5749871189a4639d84`): `mkdir -p build/models && curl -L -o build/models/deblurring_nafnet_2025may.onnx <base>/deblurring_nafnet_2025may.onnx && curl -L -o build/models/licenseplate_motion.jpg <base>/example_outputs/licenseplate_motion.jpg`

## Validation report
- Changed: files
- Checks: each check + result (pass | failure output)
- Not checked: what + why
- Docs/context: updated | no update needed
