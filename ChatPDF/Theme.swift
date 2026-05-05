import SwiftUI

//extension Color {
//    // App color palette (light mode only)
//    static let appAccent = Color.accent
//    static let appSubBackground = Color(hex: 0xF5E7C6)
//    static let appBackground = Color(hex: 0xFAF3E1)
//}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(Color.white.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

extension View {
    func cardBackground() -> some View { self.modifier(CardBackground()) }
}
