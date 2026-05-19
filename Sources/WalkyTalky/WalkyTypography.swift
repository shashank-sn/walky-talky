import SwiftUI

extension Font {
    static func walky(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func walky(_ textStyle: Font.TextStyle, weight: Font.Weight? = nil) -> Font {
        if let weight {
            return .system(textStyle, design: .rounded).weight(weight)
        }
        return .system(textStyle, design: .rounded)
    }
}

extension View {
    func walkyTracking(_ size: CGFloat) -> some View {
        tracking(size * 0.01)
    }

    func walkyDefaultTypography() -> some View {
        font(.walky(.body))
            .tracking(0.14)
    }
}
