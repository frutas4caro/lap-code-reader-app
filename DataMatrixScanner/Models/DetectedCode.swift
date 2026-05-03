import CoreGraphics
import Foundation

/// A single Data Matrix detection produced by `BarcodeScanner`.
///
/// Bounding boxes are normalised in the `0...1` range and use UIKit
/// top-left origin (Vision's bottom-left coordinates are converted
/// upstream). `rawBytes` is populated when ZXing is used as the
/// decoder of last resort for binary payloads.
public struct DetectedCode: Hashable, Codable, Sendable {
    /// Decoded payload string (e.g. `"A00011"`).
    public let payload: String
    /// Normalised bounding box in UIKit top-left coordinate space.
    public let boundingBox: CGRect
    /// Centre of `boundingBox`, cached for grid inference convenience.
    public let centroid: CGPoint
    /// Decoder confidence in the range `0...1` (`0` when unavailable).
    public let confidence: Float
    /// Raw decoded bytes when produced by the ZXing fallback. `nil`
    /// when Vision returned a usable `payloadStringValue`.
    public let rawBytes: Data?

    /// Creates a detected code. `centroid` defaults to the centre of
    /// `boundingBox` when omitted.
    public init(
        payload: String,
        boundingBox: CGRect,
        centroid: CGPoint? = nil,
        confidence: Float,
        rawBytes: Data? = nil
    ) {
        self.payload = payload
        self.boundingBox = boundingBox
        self.centroid = centroid ?? CGPoint(x: boundingBox.midX, y: boundingBox.midY)
        self.confidence = confidence
        self.rawBytes = rawBytes
    }
}
