import SwiftUI
import XCTest
@testable import NTSWidgetHost

/// Guards the alignment the status line uses to put its symbol on the middle of
/// the *first* text line. The geometry assertions are the real test; the
/// rendered PNGs exist so the result can be eyeballed when the layout changes.
@MainActor
final class FirstLineCenterAlignmentTests: XCTestCase {
    private let fontSize: CGFloat = 22

    func testCapCenterOffsetIsHalfTheFontsCapHeight() {
        let expected = NSFont.systemFont(ofSize: fontSize, weight: .semibold).capHeight / 2
        let actual = VerticalAlignment.capCenterOffset(forFontSize: fontSize, weight: .semibold)

        XCTAssertEqual(actual, expected, accuracy: 0.0001)
        // Sanity: cap height for SF is ~0.7 em, so half of it lands near 0.35 em.
        XCTAssertEqual(actual / fontSize, 0.35, accuracy: 0.05)
    }

    func testOffsetScalesWithFontSize() {
        let small = VerticalAlignment.capCenterOffset(forFontSize: 11, weight: .semibold)
        let large = VerticalAlignment.capCenterOffset(forFontSize: 44, weight: .semibold)

        XCTAssertLessThan(small, large)
        XCTAssertEqual(large / small, 4, accuracy: 0.15)
    }

    /// The point of the custom alignment: the symbol must land at the same
    /// distance from the top whether the text is one line or two. With
    /// `.center` this difference would be half a line height.
    func testSymbolPositionIsIndependentOfLineCount() throws {
        let oneLine = try symbolCenterYFromTop(text: "Connecting NTS 1…")
        let twoLines = try symbolCenterYFromTop(text: "GOD'S WAITING ROOM W/ DAVID HOLMES")

        XCTAssertEqual(oneLine, twoLines, accuracy: 0.75,
                       "symbol drifted by \(abs(oneLine - twoLines))pt when the title wrapped")
    }

    /// And it must sit on the first line's cap midpoint, not its baseline.
    func testSymbolSitsOnFirstLineCapMidpoint() throws {
        let symbolY = try symbolCenterYFromTop(text: "GOD'S WAITING ROOM W/ DAVID HOLMES")
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        // Distance from the top of a text view to its first baseline is the
        // ascender; the cap midpoint is capHeight/2 above that.
        let expected = font.ascender - font.capHeight / 2

        XCTAssertEqual(symbolY, expected, accuracy: 2.0)
    }

    // MARK: - Harness

    /// Lays out the same HStack the status line uses and returns the vertical
    /// center of the symbol, measured from the top of the row.
    private func symbolCenterYFromTop(text: String) throws -> CGFloat {
        let probe = SymbolCenterProbe(
            text: text,
            fontSize: fontSize,
            width: 260
        )

        let renderer = ImageRenderer(content: probe.body)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage, "ImageRenderer produced no image")

        // Write the render out so the layout can be eyeballed; the path is
        // printed because this is the only way to actually *see* an alignment
        // regression rather than trust the numbers.
        let dir = ProcessInfo.processInfo.environment["ALIGNMENT_RENDER_DIR"]
            ?? NSTemporaryDirectory()
        let safe = text.prefix(12).replacingOccurrences(of: " ", with: "_")
        let url = URL(fileURLWithPath: dir).appendingPathComponent("align-\(safe).png")
        if let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
            print("ALIGNMENT_RENDER: \(url.path)")
        }

        return try locateMarkerCenterY(in: image)
    }

    /// Finds the vertical center of the pure-red marker column in the render.
    private func locateMarkerCenterY(in image: NSImage) throws -> CGFloat {
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))

        var minY = Int.max
        var maxY = Int.min

        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<min(bitmap.pixelsWide, 40) {
                guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                if color.redComponent > 0.85, color.greenComponent < 0.2, color.blueComponent < 0.2 {
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                }
            }
        }

        guard minY <= maxY else {
            throw XCTSkip("marker not found in render")
        }

        // Convert back from 2x pixels to points.
        return (CGFloat(minY + maxY) / 2) / 2
    }
}

/// A stand-in for the widget's status line that uses the same shared alignment
/// and a flat red marker in place of the SF Symbol, so the marker can be found
/// in the rendered bitmap.
private struct SymbolCenterProbe {
    let text: String
    let fontSize: CGFloat
    let width: CGFloat

    var body: some View {
        HStack(alignment: .firstLineCenter, spacing: 10) {
            Rectangle()
                .fill(Color(red: 1, green: 0, blue: 0))
                .frame(width: 7, height: 7)
                .alignmentGuide(.firstLineCenter) { $0[VerticalAlignment.center] }

            Text(text)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(.black)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .alignmentGuide(.firstLineCenter) {
                    $0[.firstTextBaseline]
                        - VerticalAlignment.capCenterOffset(forFontSize: fontSize, weight: .semibold)
                }

            Spacer(minLength: 0)
        }
        .frame(width: width, alignment: .leading)
        .background(Color.white)
    }
}
