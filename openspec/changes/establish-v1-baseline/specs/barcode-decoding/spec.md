## ADDED Requirements

### Requirement: Decode Data Matrix codes from a UIImage

The system SHALL decode all Data Matrix codes present in a `UIImage` input using Apple Vision (`VNDetectBarcodesRequest` with `symbologies = [.dataMatrix]`) as the primary path. Output SHALL be a list of `RawDetection` values containing payload string, bounding box in UIKit top-left coordinate space, confidence, and (when produced by the fallback path) raw bytes.

#### Scenario: Successful decode of a multi-code image

- **WHEN** decoding a `UIImage` containing N Data Matrix codes that Vision can read
- **THEN** the result list contains N `RawDetection` entries
- **AND** each entry's `boundingBox` is a normalized `CGRect` (0–1 in each dimension) with origin at top-left

#### Scenario: Empty image produces empty result, not an error

- **WHEN** decoding a `UIImage` with no Data Matrix codes
- **THEN** the result list is empty
- **AND** no error is thrown

### Requirement: ZXing fallback for binary and missed payloads

The system SHALL invoke a ZXingObjC fallback decoder when Vision returns an observation with `payloadStringValue == nil` (binary payload) OR when Vision returns zero observations on an image whose quality analysis suggests codes are likely present (heuristic: result count < 5 on an image with normal exposure and low blur). The fallback SHALL produce `RawDetection` entries with `rawBytes` populated.

#### Scenario: Binary payload triggers fallback

- **WHEN** Vision returns an observation with non-nil `boundingBox` but nil `payloadStringValue`
- **THEN** the system invokes ZXingObjC on the cropped region
- **AND** the resulting `RawDetection` has `rawBytes` populated

#### Scenario: Suspiciously low Vision result triggers full-image fallback

- **WHEN** image quality analysis reports low blur and normal exposure
- **AND** Vision returns fewer than 5 observations
- **THEN** the system runs ZXingObjC on the full image
- **AND** merges any additional detections into the result list, deduplicated by bounding-box overlap

### Requirement: Bounding boxes use UIKit top-left origin

The system SHALL convert Vision's bottom-left-origin normalized rects to UIKit top-left-origin before storing or returning them. Conversion: `flipped.y = 1 - box.origin.y - box.height`.

#### Scenario: Coordinate conversion

- **WHEN** Vision returns a bounding box `(x: 0.1, y: 0.2, w: 0.3, h: 0.4)` in bottom-left space
- **THEN** the stored `RawDetection.boundingBox` is `(x: 0.1, y: 0.4, w: 0.3, h: 0.4)` in top-left space

### Requirement: Best-effort under decode failure

The system SHALL NOT throw `ScanError.decodeFailed` for transient input issues (poor lighting, blur, partial occlusion). Decode SHALL only fail when the underlying `CGImage` cannot be obtained from the `UIImage` or when Vision throws a non-recoverable system error.

#### Scenario: Blurry image returns partial results, not an error

- **WHEN** decoding a blurry image that yields three confident detections and several low-confidence ones
- **THEN** the result list contains the three confident detections
- **AND** no error is thrown

#### Scenario: Corrupted UIImage throws decodeFailed

- **WHEN** the input `UIImage` cannot produce a `CGImage`
- **THEN** the decoder throws `ScanError.decodeFailed(underlying:)`
