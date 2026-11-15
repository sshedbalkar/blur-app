# Technical requirements

Each names need served (TR-3). Code locations: `context/ROUTING.md`.

## TR-1: Feature interface
- All features implement `Feature`: id, name, description, params, `run`.
- Each param declares type + supported range (`NumParam` min/max, `ChoiceParam` options, `BoolParam`).
- Values coerced into range before run, any source (UI, AI, code).
- Serves: UX-1, UX-2, UX-3.

## TR-2: Persistent local logs
- Logged to file: every user interaction, every user input, every non-trivial app decision, plus normal diagnostics.
- File: `blur-app_YYYY-MM-DD.log`, one per day. Creation time in name optional; unused.
- Format: JSON object per line: `time`, `kind` (`interaction`|`input`|`decision`|`info`|`error`), `event`, `data`.
- Default dir: `$XDG_STATE_HOME/blur-app/logs` (fallback `~/.local/state`). User-changeable in Settings.
- Log failure never stops app.
- Serves: debugging.

## TR-3: Nothing without purpose
- Every requirement and piece of code serves UX requirement, product requirement, debugging, or optimization. Not needed in current end-user context -> not in live version.

## TR-4: Front-end stack
- Flutter (Dart), Linux desktop, Material. Why: D-1.
- Complicated/performance-critical feature work -> native via `dart:ffi`. Rest in Dart.
- Serves: all UX; dev speed.

## TR-5: Security
- Not required while app is front-end only and local. Revisit on remote input or non-local services.

## TR-6: Central global settings
- All global settings defined in one file, machine-suited defaults, one Settings screen, user-changeable.
- Stored: `$XDG_CONFIG_HOME/blur-app/settings.json` (fallback `~/.config`).
- Missing/damaged file -> defaults.
- Serves: UX-5.

## TR-7: Local AI access
- OpenAI-compatible HTTP API on local server. Address + model = settings.
- Model only proposes. App validates against registry + param ranges.
- Serves: UX-1, UX-3, UX-4.
