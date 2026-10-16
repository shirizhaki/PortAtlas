import SwiftUI

@main
struct PortAtlasApp: App {
    @NSApplicationDelegateAdaptor(AtlasApplicationDelegate.self) private var applicationDelegate
    @StateObject private var store = AtlasStore()
    var body: some Scene {
        WindowGroup {
            AtlasView().environmentObject(store)
                .modifier(AppAppearancePreference())
                .frame(minWidth: 1000, maxWidth: .infinity, minHeight: 680, maxHeight: .infinity)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
                       let icon = NSImage(contentsOf: url) {
                        NSApp.applicationIconImage = icon
                    }
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 1260, height: 810)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh Connections") { store.refresh() }.keyboardShortcut("r")
            }
            CommandGroup(after: .toolbar) {
                Divider()
                Button("Fit All") { store.fitRevision += 1 }.keyboardShortcut("0")
                Button("Focus Selection") { store.focusRevision += 1 }.keyboardShortcut("2").disabled(store.selection == nil)
                Button("Switch Map View") { store.activeMapKind = store.activeMapKind == .physical ? .logical : .physical }.keyboardShortcut("1")
            }
        }
        Settings {
            PortSettingsView().environmentObject(store)
                .modifier(AppAppearancePreference())
                .frame(width: 740, height: 620)
        }
    }
}

final class AtlasApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        let saved = UserDefaults.standard.string(forKey: AppAppearance.preferenceKey) ?? ""
        (AppAppearance(rawValue: saved) ?? .system).apply()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
