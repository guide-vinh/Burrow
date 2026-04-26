import SwiftUI

/// Coral-filled rounded square with a white tornado glyph. Brand mark
/// used in the sidebar header.
struct BrandLogo: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Color.accentPrimary)
            Image(systemName: "tornado")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Color.fgInverse)
        }
        .frame(width: 32, height: 32)
    }
}

struct BrandLogo_Previews: PreviewProvider {
    static var previews: some View {
        BrandLogo()
            .padding()
    }
}
