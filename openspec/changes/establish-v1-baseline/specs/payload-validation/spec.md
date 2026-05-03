## ADDED Requirements

### Requirement: Configurable regex validator

The system SHALL provide a `PayloadValidator` service that compiles a regex from `@AppStorage` key `validatorRegex` and offers a pure `matches(_ payload: String) -> Bool` function. The CEL default value SHALL be `^[A-Z]\d{5}$`. The regex SHALL be re-compiled when the stored value changes.

#### Scenario: Default regex matches CEL convention

- **WHEN** `validatorRegex` is unset (first launch)
- **THEN** `matches("A00011")` returns `true`
- **AND** `matches("AOO011")` returns `false` (letter O instead of zero)

#### Scenario: User changes regex, validator re-compiles

- **WHEN** the user updates `validatorRegex` in Settings to `^[A-Z]{2}\d{4}$`
- **THEN** subsequent calls to `matches("AB1234")` return `true`
- **AND** `matches("A00011")` returns `false`

### Requirement: Partition raw detections into decoded vs. rejected

The system SHALL partition `[RawDetection]` into two sublists based on `validator.matches(payload)`. Rejected detections SHALL NOT be discarded; they SHALL be passed downstream to `grid-inference` so they can become `unreadable.validatorRejected` cells.

#### Scenario: Mixed input partitions correctly

- **WHEN** the validator regex is the default and the input is `["A00011", "B00042", "AOO011", "FOO"]`
- **THEN** the decoded list contains `["A00011", "B00042"]`
- **AND** the rejected list contains `["AOO011", "FOO"]`
- **AND** both lists preserve each entry's original `boundingBox`

### Requirement: Re-validation is a pure function over stored payloads

The system SHALL support re-validating any historical `StoredScan` against the *current* `validatorRegex` without mutating stored data. The function `revalidate(scan: StoredScan, regex: String) -> [GridCell]` SHALL apply the new regex to the scan's stored raw payloads and return updated cell statuses. The original `validatorRegexAtCapture` field on `StoredScan` SHALL remain immutable.

#### Scenario: Regex change propagates to historical view

- **GIVEN** a historical scan captured with regex `^[A-Z]\d{5}$` containing payload `"AB1234"` (rejected at capture)
- **WHEN** the user changes the regex to `^[A-Z]{2}\d{4}$` and reopens the scan
- **THEN** the cell containing `"AB1234"` displays as `decoded`, not `unreadable.validatorRejected`
- **AND** `StoredScan.validatorRegexAtCapture` still equals `^[A-Z]\d{5}$`

#### Scenario: Audit recovery via captured regex

- **WHEN** an auditor needs to know what verdict a historical scan received at the time it was captured
- **THEN** `StoredScan.validatorRegexAtCapture` provides the original regex
- **AND** the auditor can call `revalidate(scan:, regex: scan.validatorRegexAtCapture)` to reproduce the original cell statuses
