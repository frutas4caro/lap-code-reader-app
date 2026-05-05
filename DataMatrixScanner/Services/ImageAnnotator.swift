import CoreGraphics
import Foundation
import UIKit

/// Renders an annotated overlay (bounding boxes + payload labels) onto a
/// scan source image.
///
/// This is the v1.0 walking-skeleton implementation: a CPU-backed
/// `UIGraphicsImageRenderer` pass that draws the *Per-Cell Overlay* color
/// matrix from `docs/annotation-spec.md` at minimal fidelity. Grid lines,
/// row/column edge labels, GPU-backed `CIContext` rendering, and the
/// 2-second performance gate are deferred to other `dms-d6u.*` children.
///
/// The annotator is `Sendable` and stateless — callers may share a single
/// instance across tasks.
///
/// ## Coordinate space
/// Cell bounding boxes are normalised to the `0...1` range in UIKit
/// top-left origin space (Vision-to-UIKit conversion happens upstream in
/// `BarcodeScanner`). They are denormalised against the input image's
/// `size` to obtain pixel coordinates.
///
/// ## Empty cells
/// `.fixed`-layout `.empty` cells have no detection bounding box in v1.0,
/// so they are skipped here. A future revision (see `docs/annotation-spec.md`)
/// will reconstruct ideal-position rectangles from the inferred grid axes
/// and stroke them in dashed yellow.
public struct ImageAnnotator: Sendable {

    /// Stroke weight in points (in image-pixel space). Spec: 3pt.
    private static let strokeWidth: CGFloat = 3

    /// Minimum and maximum label font sizes, scaled by bounding-box width.
    private static let minFontSize: CGFloat = 10
    private static let maxFontSize: CGFloat = 24

    /// Decoded-cell stroke color (`#00FF88`).
    private static let decodedColor = UIColor(
        red: 0x00 / 255.0, green: 0xFF / 255.0, blue: 0x88 / 255.0, alpha: 1
    )

    /// User-edited or user-added cell stroke color (`#3B82F6`).
    private static let editedColor = UIColor(
        red: 0x3B / 255.0, green: 0x82 / 255.0, blue: 0xF6 / 255.0, alpha: 1
    )

    /// Unreadable-cell stroke color (`#FF8C00`).
    private static let unreadableColor = UIColor(
        red: 0xFF / 255.0, green: 0x8C / 255.0, blue: 0x00 / 255.0, alpha: 1
    )

    /// Outlier-cell stroke color (`#FFCC00`).
    private static let outlierColor = UIColor(
        red: 0xFF / 255.0, green: 0xCC / 255.0, blue: 0x00 / 255.0, alpha: 1
    )

    /// Creates a stateless annotator.
    public init() {}

    /// Returns a new `UIImage` with per-cell overlays drawn on top of `image`.
    ///
    /// The output preserves the input's `size`, `scale`, and orientation.
    /// Cells whose effective bounding box is `nil` (notably `.empty` cells
    /// in fixed-layout mode) are skipped — they have no spatial anchor in
    /// v1.0.
    ///
    /// - Parameters:
    ///   - image: The source scan image.
    ///   - cells: Grid cells produced by the scan pipeline.
    /// - Returns: A new image of identical dimensions; if `cells` is empty
    ///   the input is returned unchanged.
    public func annotate(image: UIImage, cells: [GridCell]) -> UIImage {
        guard !cells.isEmpty else { return image }

        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)

        return renderer.image { context in
            // Draw the source image as the base layer.
            image.draw(in: CGRect(origin: .zero, size: image.size))

            for cell in cells {
                draw(cell: cell, in: context.cgContext, imageSize: image.size)
            }
        }
    }

    // MARK: - Private

    /// Draws a single cell's overlay (stroke + label) into `cgContext`.
    private func draw(
        cell: GridCell,
        in cgContext: CGContext,
        imageSize: CGSize
    ) {
        guard
            let normalisedBox = boundingBox(for: cell),
            let style = renderStyle(for: cell)
        else {
            return
        }

        let pixelRect = denormalise(normalisedBox, in: imageSize)

        // Stroke the bounding box.
        cgContext.saveGState()
        cgContext.setStrokeColor(style.color.cgColor)
        cgContext.setLineWidth(Self.strokeWidth)
        cgContext.setLineJoin(.round)
        cgContext.stroke(pixelRect)
        cgContext.restoreGState()

        // Label above (or below, if there isn't room above).
        drawLabel(style.label, near: pixelRect, imageSize: imageSize)
    }

    /// Returns the bounding box to render against, accounting for the
    /// `userOverride` and outlier branches.
    private func boundingBox(for cell: GridCell) -> CGRect? {
        switch cell.status {
        case .decoded(let code):
            return code.boundingBox
        case .unreadable(_, let bbox):
            return bbox
        case .empty:
            return nil
        }
    }

    /// Resolves the (color, label) pair for a cell.
    private func renderStyle(for cell: GridCell) -> (color: UIColor, label: String)? {
        // Outliers take precedence: they are decoded codes outside the
        // declared layout. Spec: solid yellow, label = "<payload> outlier".
        if cell.isOutlier {
            if case .decoded(let code) = cell.status {
                let payload = cell.userOverride ?? code.payload
                return (Self.outlierColor, "\(payload) outlier")
            }
            // Outlier without a decoded payload is not a v1.0 case; skip.
            return nil
        }

        switch cell.status {
        case .decoded(let code):
            if let override = cell.userOverride, !override.isEmpty {
                return (Self.editedColor, override)
            }
            if cell.userAdded {
                return (Self.editedColor, code.payload)
            }
            return (Self.decodedColor, code.payload)

        case .unreadable(let reason, _):
            switch reason {
            case .decodeFailed:
                return (Self.unreadableColor, "unreadable")
            case .validatorRejected(let payload):
                return (Self.unreadableColor, "rejected: \(payload)")
            case .lowConfidence:
                return (Self.unreadableColor, "low conf")
            }

        case .empty:
            // No bbox in v1.0; caller filters this out.
            return nil
        }
    }

    /// Converts a normalised UIKit-space rect to image-pixel coordinates.
    private func denormalise(_ box: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: box.origin.x * size.width,
            y: box.origin.y * size.height,
            width: box.width * size.width,
            height: box.height * size.height
        )
    }

    /// Draws a label pill above (or below) `pixelRect`.
    private func drawLabel(
        _ text: String,
        near pixelRect: CGRect,
        imageSize: CGSize
    ) {
        let fontSize = max(
            Self.minFontSize,
            min(Self.maxFontSize, pixelRect.width * 0.18)
        )
        let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)

        let padding: CGFloat = max(4, fontSize * 0.3)
        let textSize = attributed.size()
        let pillHeight = textSize.height + padding * 2
        let pillWidth = textSize.width + padding * 2

        // Prefer placing the pill above the bbox; fall back to below if the
        // bbox is too close to the top edge.
        let pillY: CGFloat
        if pixelRect.minY - pillHeight >= 0 {
            pillY = pixelRect.minY - pillHeight
        } else if pixelRect.maxY + pillHeight <= imageSize.height {
            pillY = pixelRect.maxY
        } else {
            // No clean spot: clamp inside the bbox at the top.
            pillY = max(0, pixelRect.minY)
        }

        // Clamp horizontally so the pill stays inside the image.
        let rawX = pixelRect.minX
        let pillX = max(0, min(rawX, imageSize.width - pillWidth))

        let pillRect = CGRect(
            x: pillX,
            y: pillY,
            width: pillWidth,
            height: pillHeight
        )

        // Pill background: black @ 65%.
        let pillPath = UIBezierPath(
            roundedRect: pillRect,
            cornerRadius: pillHeight / 2
        )
        UIColor.black.withAlphaComponent(0.65).setFill()
        pillPath.fill()

        // Text.
        let textOrigin = CGPoint(
            x: pillRect.minX + padding,
            y: pillRect.minY + padding
        )
        attributed.draw(at: textOrigin)
    }
}
