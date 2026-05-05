import CoreGraphics
import Foundation
import Vision

/// Vision-only Data Matrix decoder.
///
/// Wraps `VNDetectBarcodesRequest` with `symbologies = [.dataMatrix]`,
/// converts each `VNBarcodeObservation`'s normalised bottom-left
/// bounding box into UIKit top-left space, and returns the result as
/// `[DetectedCode]`.
///
/// v1.0 is Vision-only by design. Observations whose
/// `payloadStringValue` is `nil` (binary payloads) are dropped
/// silently here; the ZXing fallback that recovers them is tracked
/// separately as `dms-u9v` and ships in v1.1.
///
/// Empty results are NOT an error — only a thrown
/// `VNImageRequestHandler.perform` failure is surfaced, wrapped as
/// `ScanError.decodeFailed(underlying:)`.
public actor BarcodeScanner {
    /// Creates a Vision-backed Data Matrix scanner.
    public init() {}

    /// Scans the supplied `CGImage` for Data Matrix codes.
    ///
    /// - Parameter cgImage: full-resolution image to decode.
    /// - Returns: zero or more detected codes. Bounding boxes are
    ///   normalised (`0...1`) and use UIKit top-left origin.
    /// - Throws: `ScanError.decodeFailed(underlying:)` only when
    ///   Vision itself raises during `perform`. Empty arrays are not
    ///   errors.
    public func scan(cgImage: CGImage) async throws -> [DetectedCode] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.dataMatrix]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw ScanError.decodeFailed(underlying: error)
        }

        let observations = request.results ?? []
        return observations.compactMap(Self.detectedCode(from:))
    }

    /// Converts a single Vision observation into a `DetectedCode`,
    /// flipping the bounding box origin from bottom-left to top-left.
    /// Returns `nil` for binary payloads (no `payloadStringValue`) —
    /// see ZXing fallback bead `dms-u9v`.
    private static func detectedCode(from observation: VNBarcodeObservation) -> DetectedCode? {
        // TODO(dms-u9v): route nil payloadStringValue through ZXing fallback.
        guard let payload = observation.payloadStringValue else { return nil }

        let box = observation.boundingBox
        let flipped = CGRect(
            x: box.origin.x,
            y: 1 - box.origin.y - box.height,
            width: box.width,
            height: box.height
        )

        return DetectedCode(
            payload: payload,
            boundingBox: flipped,
            confidence: Float(observation.confidence)
        )
    }
}
