import SwiftUI
import AppKit

/// The shared PiaoPal palette keeps every window and exported card readable.
extension Color {
    static let piaCanvas = Color(red: 0.969, green: 0.961, blue: 0.937)
    static let piaSurface = Color.white
    static let piaInk = Color(red: 0.20, green: 0.25, blue: 0.22)
    static let piaMuted = Color(red: 0.39, green: 0.44, blue: 0.40)
    static let piaAccent = Color(red: 0.31, green: 0.42, blue: 0.34)
    static let piaWash = Color(red: 0.91, green: 0.94, blue: 0.89)
    static let piaBorder = Color(red: 0.85, green: 0.88, blue: 0.83)
}

extension NSColor {
    static let piaCanvas = NSColor(red: 0.969, green: 0.961, blue: 0.937, alpha: 1)
}

extension View {
    func companionPanel() -> some View {
        self.padding(18)
            .background(Color.piaSurface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.piaBorder, lineWidth: 1))
    }
}
