import SwiftUI

@main
struct PortAtlasApp: App {
    @NSApplicationDelegateAdaptor(AtlasApplicationDelegate.self) private var applicationDelegate
    @StateObject private var store = AtlasStore()
    var body: some Scene {
        WindowGroup {
            AtlasView().environmentObject(store)
                .modifier(AppAppearancePreference())
                .frame(minWidth: 1100, maxWidth: .infinity, minHeight: 680, maxHeight: .infinity)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 1440, height: 880)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh Connections") { store.refresh() }.keyboardShortcut("r")
            }
            CommandGroup(after: .toolbar) {
                Divider()
                Button("Physical Map") { store.activeMapKind = .physical }.keyboardShortcut("1")
                Button("Logical Map") { store.activeMapKind = .logical }.keyboardShortcut("2")
                Divider()
                Button("Zoom In") { store.requestZoom(1) }.keyboardShortcut("=")
                Button("Zoom Out") { store.requestZoom(-1) }.keyboardShortcut("-")
                Button("Fit All") { store.fitRevision += 1 }.keyboardShortcut("0")
                Button("Focus Selection") { store.focusRevision += 1 }.keyboardShortcut("l").disabled(store.selection == nil)
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
