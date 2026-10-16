import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    static let preferenceKey = "appAppearance"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "Follow System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    @MainActor func apply() {
        let name: NSAppearance.Name?
        switch self {
        case .system: name = nil
        case .light: name = .aqua
        case .dark: name = .darkAqua
        }
        // AppKit controls and visual-effect materials share the SwiftUI appearance.
        // A nil override lets macOS continue updating the app automatically.
        if NSApp.appearance?.name != name {
            NSApp.appearance = name.flatMap { NSAppearance(named: $0) }
        }
    }
}

struct AppAppearancePreference: ViewModifier {
    @AppStorage(AppAppearance.preferenceKey) private var appearance: AppAppearance = .system
    func body(content: Content) -> some View {
        content
            .onAppear { appearance.apply() }
            .onChange(of: appearance) { _, value in value.apply() }
    }
}
