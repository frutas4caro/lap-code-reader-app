# DataMatrix Grid Scanner — iOS App

Scans photos containing 1–100 Data Matrix codes arranged in a grid pattern.
Detects all codes, records positions, infers grid structure (rows/columns),
returns an annotated photo and exportable CSV. iPhone only, iOS 17+.

## Tech Stack
- Language: Swift 5.10, SwiftUI
- Barcode decode: Apple Vision (VNDetectBarcodesRequest, .dataMatrix)
- Fallback decode: ZXingObjC via SPM (binary payloads, Vision misses)
- Image annotation: Core Graphics / Core Image
- Grid inference: custom geometry engine (see @docs/grid-inference.md)
- Persistence: SwiftData
- Camera/import: AVFoundation + PhotosUI
- Tests: XCTest + Swift Testing
- CI: Xcode Cloud

## Key Commands
- Build: `xcodebuild -scheme DataMatrixScanner -destination 'platform=iOS Simulator,name=iPhone 16'`
- Test: `xcodebuild test -scheme DataMatrixScanner -destination 'platform=iOS Simulator,name=iPhone 16'`
- Lint: `swiftlint lint --strict`
- Testbed: `swift run TestBed TestImages/`

## Code Rules
- MVVM strictly: Views own no business logic
- All Vision/CoreGraphics work on background queues; UI updates on @MainActor
- Swift Concurrency (async/await) only — no completion handler callbacks
- Prefer structs; use classes only when reference semantics required
- Every public function requires a doc comment
- Never force-unwrap; use guard-let or Result types

## Docs — Read Before Working on That Area
- @docs/architecture.md       — module map, data flow, key types
- @docs/implementation-plan.md — phased tasks with [ ] checkboxes
- @docs/vision-api-notes.md   — Data Matrix decode specifics, edge cases
- @docs/grid-inference.md     — grid detection algorithm and geometry
- @docs/annotation-spec.md    — annotated image output specification
- @docs/csv-export-spec.md    — CSV format, copy/share behaviour
- @docs/testbed-workflow.md   — how to run batch tests against TestImages/

## Distribution
Single CEL-branded App Store binary ("DataMatrix Grid Scanner"). Defaults are
CEL-flavored (`[A-Z]\d{5}` validator regex, 9×9 default box layout, provenance
column on, 30-day / 1 GB photo retention). Every default is overridable in
Settings — there is no separate "public" build.

## Gotchas
- **Validator regex is configurable** — read it from `@AppStorage` via
  `PayloadValidator`. The CEL pattern `^[A-Z]\d{5}$` is the default, NOT a
  hardcoded constant. Codes that decode but fail the current regex become
  `CellStatus.unreadable(.validatorRejected(...))` — they are NOT silently
  dropped.
- Up to 100 codes per image: Vision handles this fine but annotation
  rendering must not degrade — use CIContext with GPU backing.
- Grid may be rotated relative to photo — do NOT assume axis-alignment.
- Grid may have missing cells — do NOT assume a complete rectangular grid.
  In `.fixed(rows, cols)` layout mode, the inferred grid always has exactly
  `rows × cols` cells regardless of how many codes were detected.
- Binary payloads: observation.payloadStringValue may be nil — use ZXingObjC.
- Camera permission denied must be handled explicitly, never silently.
- The pipeline is **best-effort, never abort**. Decode/validation/inference
  failures produce a `ScanResult` with `unreadable` cells and warnings — only
  `permissionDenied`, `imageTooLarge`, and true `decodeFailed(underlying:)`
  ever flow through the `ScanError` path.
- Missing cells in CSV output are the literal string `null`, not blank.


<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:ca08a54f -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

## Session Completion

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd dolt push
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
<!-- END BEADS INTEGRATION -->
