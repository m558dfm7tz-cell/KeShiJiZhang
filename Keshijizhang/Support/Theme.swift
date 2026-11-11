import SwiftUI

enum Theme {
    static let bg = Color(red: 0.949, green: 0.949, blue: 0.969)
    static let card = Color.white
    static let blue = Color(red: 0.0, green: 0.478, blue: 1.0)
    static let green = Color(red: 0.204, green: 0.780, blue: 0.349)
    static let red = Color(red: 1.0, green: 0.231, blue: 0.188)
    static let purple = Color(red: 0.608, green: 0.318, blue: 0.878)
    static let orange = Color(red: 1.0, green: 0.584, blue: 0.0)
    static let secondary = Color(red: 0.557, green: 0.557, blue: 0.576)
    static let separator = Color.black.opacity(0.06)
    static let chipIdle = Color.white
    static let field = Color(red: 0.949, green: 0.949, blue: 0.969)
    static let radius: CGFloat = 16
}

extension Color {
    static let themeBlue = Theme.blue
    static let themeGreen = Theme.green
    static let themeRed = Theme.red
    static let themePurple = Theme.purple
    static let themeOrange = Theme.orange
}
