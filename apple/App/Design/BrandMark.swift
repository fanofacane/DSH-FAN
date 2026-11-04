// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

/// Placeholder brand glyph (tail + bubble) borrowed from DSH Go; replace with DSH Fan's own mark before release (see THIRD_PARTY_NOTICES.md).
struct BrandMark: View {
    var size: CGFloat = 30
    var body: some View {
        Image("BrandGlyph").resizable().scaledToFit().frame(width: size, height: size).accessibilityHidden(true)
    }
}
