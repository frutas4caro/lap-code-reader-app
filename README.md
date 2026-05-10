# lab-code-reader
Datamatrix reader ios app

## Integration Test Reference Files

Test corpus lives at `TestImages/`. The going-forward format is a
**TestCaseBundle directory** — see `docs/testbed-workflow.md` for the full
spec. Each bundle contains:

| File | Purpose |
|------|---------|
| `input.jpg` | Full-resolution source image |
| `expected.csv` | Ground truth in v1 CSV schema (`row,col,code`, provenance OFF, `null` for empty/unreadable, every (row,col) enumerated) |
| `detected.json` | Raw Vision/ZXing output — present for app-exported bundles, absent for hand-built seeds |
| `metadata.json` | Capture context: device, iOS, app version, validator regex, layout mode |
| `annotated.jpg` | Optional visual reference; no test asserts on this |

The seed bundle is `TestImages/46__sparsed_missing/`. Its `expected.csv` will
be generated during v1 dogfooding by hand-correcting the first pipeline run
on `input.jpg`.

**Xcode setup:** `TestImages/` is exposed to the test target as a
Swift Package resource. `ScanPipelineIntegrationTests.swift` loads bundles
via `Bundle.module.url(forResource:withExtension:subdirectory:)`. The
TestBed CLI reads the same directory directly from disk. Single source of
truth, no duplication into Copy Bundle Resources.

**Pass thresholds (per `docs/testbed-workflow.md`):** ≥ 95% image-level
decoded-count match AND ≥ 99% per-cell match across the corpus.

## Color Palette

Defined in `Color+AppColors.swift` as static extensions on `Color`. All UI code must use these instead of system colors.

| Token | Hex | Role |
|---|---|---|
| `.appBlue` | `#207dbb` | Primary action, buttons, slider tint |
| `.appPurple` | `#775f9a` | Accent / secondary highlight |
| `.appOrange` | `#ea6d29` | Warnings / emphasis |
| `.appYellow` | `#edb837` | Badges / status indicators |
| `.appGreen` | `#1f9591` | Success / confirmed states |
| `.appRed` | `#a6213b` | Errors, EMPTY cell labels |
| `.appLightBlue` | `#67bddf` | Hover / selection tint |
| `.appLightTeal` | `#e6f4ef` | Surface / card backgrounds |
| `.appGray` | `#6d6e71` | Secondary text, disabled states |
| `.appLightestBlue` | `#e4f1fb` | Controls panel background |

Color assets live in `Assets.xcassets` as named `AppBlue.colorset`, etc., allowing future dark-mode variants to be added without code changes.
# lap-code-reader-app
