# Agent rules

Blur App: local Linux desktop media toolbox, Flutter. Features = plug-ins behind one interface. Local AI model: plain-language request -> feature commands + suggested params.

Start: `context/ROUTING.md`. Source = truth; map only points.

## Rules
1. Clarity >95% before any project/repo change. Lower -> ask.
2. Significant design/UX change or durable decision -> update matching doc, same change:
   - `UX_REQUIREMENTS.md`: user-facing behaviour, status
   - `TECHNICAL_REQUIREMENTS.md`: constraints + need served
   - `DESIGN.md`: decisions + why
3. Structure/entry-point/convention change -> update `context/`, same change.
4. Validate every change. End response with validation report.
5. Nothing speculative. Each technical addition serves UX/product requirement, debugging, or optimization (TR-3). Else omit.
6. All `.md` files, repo-wide: written for AI models. Clear, zero redundancy, minimal words, grammar optional, pointers over prose. One fact, one place; elsewhere reference it.

## Validation
From repo root. `flutter` not on PATH -> `~/.local/share/flutter/bin`.

| Change | Run |
| --- | --- |
| Dart code | `dart format lib test`; `flutter analyze`; `flutter test` |
| UI behaviour | above + widget test for change |
| Linux runner, native/FFI, deps | above + `flutter build linux` |
| `.md` only | referenced paths exist; rule 6 |

## Validation report
- Changed: files
- Checks: each check + result (pass | failure output)
- Not checked: what + why
- Docs/context: updated | no update needed
