import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Aligns a leading symbol with the optical middle of a text's **first** line,
/// so it stays put whether the text occupies one line or wraps to several.
///
/// Neither built-in alignment does this:
///
/// - `.firstTextBaseline` aligns the symbol's own text baseline to the text
///   baseline, which leaves a small glyph (`circle.fill`) sitting *on* the
///   baseline instead of centered on the line.
/// - `.center` centers against the whole text block, so the symbol drifts
///   downward as soon as the text wraps to a second line.
///
/// Usage:
/// ```
/// HStack(alignment: .firstLineCenter) {
///     symbol.alignmentGuide(.firstLineCenter) { $0[VerticalAlignment.center] }
///     Text(title)
///         .alignmentGuide(.firstLineCenter) {
///             $0[.firstTextBaseline] - VerticalAlignment.capCenterOffset(forFontSize: 22, weight: .semibold)
///         }
/// }
/// ```
enum FirstLineCenterAlignmentID: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat {
        context[VerticalAlignment.center]
    }
}

extension VerticalAlignment {
    static let firstLineCenter = VerticalAlignment(FirstLineCenterAlignmentID.self)

    /// Distance from a line's baseline up to its cap-height midpoint — the
    /// offset that turns `firstTextBaseline` into "middle of the first line".
    ///
    /// Cap height rather than x-height because the content here is largely
    /// uppercase show titles. Measured from the real font so it survives a font
    /// size or weight change instead of drifting with a hardcoded guess.
    static func capCenterOffset(forFontSize size: CGFloat, weight: NSFont.Weight = .regular) -> CGFloat {
        #if canImport(AppKit)
        return NSFont.systemFont(ofSize: size, weight: weight).capHeight / 2
        #else
        // SF's cap height is ~0.72 em; halved.
        return size * 0.36
        #endif
    }
}
