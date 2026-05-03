# Apple Vision — Data Matrix Notes

## Decode Call
```swift
let request = VNDetectBarcodesRequest()
request.symbologies = [.dataMatrix]
let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
try handler.perform([request])
let observations = request.results as? [VNBarcodeObservation] ?? []
```

## Payload Validation
Validation is performed by the `PayloadValidator` service, which reads the
current regex from `@AppStorage` (default: `^[A-Z]\d{5}$`, the CEL pattern).
The regex is **user-configurable in Settings** — never hardcode it.

```swift
let validator = PayloadValidator(pattern: settings.validatorRegex)
let (decoded, rejected) = observations.partition { obs in
    validator.matches(obs.payloadStringValue ?? "")
}
```

Rejected observations are NOT discarded. They become
`CellStatus.unreadable(reason: .validatorRejected(decodedPayload: ...))` so
the user can see what was decoded, why it was rejected, and act on it
(manual fix, relax validator, etc.). The `RemediationAdvisor` provides the
per-cell recommendation; the editor pre-fills the rejected payload with
non-matching characters highlighted.

## Bounding Box Conversion
Vision returns normalised CGRect in bottom-left origin space.
Convert to UIKit top-left origin before storing:
```swift
let flipped = CGRect(
    x: box.origin.x,
    y: 1 - box.origin.y - box.height,
    width: box.width,
    height: box.height
)
```

## ZXingObjC Fallback
Trigger when payloadStringValue is nil (binary payload) or when Vision
returns 0 results but image quality suggests codes are present.
Wrap in ZXingWrapper.swift — single file, isolates ObjC bridging.

## Known Edge Cases
- Dense grids (>50 codes): Vision handles well; ensure CGImage is full res.
- Rotated images: Vision is rotation-invariant, no pre-rotation needed.
- Poor lighting: add CIColorControls (contrast +0.3) before passing to Vision
  if initial decode returns fewer codes than expected (heuristic: retry if
  result count is suspiciously low, e.g. <5 on a high-res image).
