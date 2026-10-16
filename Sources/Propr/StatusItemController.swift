import AppKit
import Combine
import SwiftUI

// Full AppKit status item for reliable menubar menu (no SwiftUI hover flicker).
// This gives native macOS menu behavior including proper hover highlighting on submenus.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    static let shared = StatusItemController()
    
    private var statusItem: NSStatusItem?
    private var permissionCancellable: AnyCancellable?
    private var modelChangeObserver: NSObjectProtocol?
    
    private override init() {
        super.init()
    }
    
    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(named: "MenuBarIcon")
            button.image?.isTemplate = true
        }
        
        let menu = buildMainMenu()
        menu.delegate = self
        statusItem?.menu = menu

        // Live update the menu when permission state changes (so "Permissions & Setup..."
        // disappears immediately after the user grants it, without needing to re-open the menu).
        permissionCancellable = AccessibilityManager.shared.$hasPermission
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshMenu()
            }

        modelChangeObserver = NotificationCenter.default.addObserver(
            forName: .proprModelStoreDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshMenu()
            }
        }
    }
    
    /// Forces a fresh permission check + rebuild of the dynamic parts of the menu.
    /// Safe to call from anywhere (e.g. when permission is granted from the onboarding window).
    func refreshMenu() {
        AccessibilityManager.shared.checkPermission(prompt: false)

        let freshMenu = buildMainMenu()
        freshMenu.delegate = self
        statusItem?.menu = freshMenu
    }
    
    private func buildMainMenu() -> NSMenu {
        let menu = NSMenu()
        
        // Show Floating Bar
        let showBar = NSMenuItem(title: "Show Floating Bar", action: #selector(showFloatingBar), keyEquivalent: "")
        showBar.target = self
        menu.addItem(showBar)
        
        menu.addItem(.separator())
        
        // Model submenus (dynamic). Default and lookup are separate choices, so
        // they get separate submenus rather than one list with two checkmarks.
        let modelMenu = buildModelSubmenu()
        let modelItem = NSMenuItem(title: "Refine Model...", action: nil, keyEquivalent: "")
        modelItem.submenu = modelMenu
        menu.addItem(modelItem)
        
        let lookupMenu = buildLookupModelSubmenu()
        let lookupItem = NSMenuItem(title: "Lookup Model...", action: nil, keyEquivalent: "")
        lookupItem.submenu = lookupMenu
        menu.addItem(lookupItem)
        
        menu.addItem(.separator())
        
        // Settings
        let settings = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        
        // Permissions & Setup (only when accessibility is missing)
        // This keeps the menu in sync with reality so users don't get surprised by the
        // onboarding window on launch when permissions are actually fine.
        if !AccessibilityManager.shared.hasPermission {
            let perms = NSMenuItem(title: "Permissions & Setup...", action: #selector(openPermissions), keyEquivalent: "")
            perms.target = self
            if let icon = NSImage(systemSymbolName: "exclamationmark.shield", accessibilityDescription: "Permissions") {
                icon.isTemplate = true
                perms.image = icon
            }
            menu.addItem(perms)
        }
        
        menu.addItem(.separator())
        
        // Quit
        let quit = NSMenuItem(title: "Quit Propr", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        if let icon = NSImage(systemSymbolName: "power", accessibilityDescription: "Quit") {
            icon.isTemplate = true
            quit.image = icon
        }
        menu.addItem(quit)
        
        return menu
    }
    
    private func buildModelSubmenu() -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        
        let models = ModelStore.shared.allAvailableModels
        
        if models.isEmpty {
            let item = NSMenuItem(title: "No models configured", action: nil, keyEquivalent: "")
            item.isEnabled = false
            submenu.addItem(item)
        } else {
            for model in models {
                let item = NSMenuItem(title: model.displayName, action: #selector(selectModel(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = model.id.uuidString
                
                if model.id == ModelStore.shared.selectedModelID {
                    item.state = .on
                }
                
                submenu.addItem(item)
            }
        }
        
        submenu.addItem(.separator())
        
        let manage = NSMenuItem(title: "Manage Models...", action: #selector(openManageModels), keyEquivalent: "")
        manage.target = self
        submenu.addItem(manage)
        
        return submenu
    }
    
    private func buildLookupModelSubmenu() -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        
        let items = ModelStore.lookupModelMenuItems(
            lookupID: ModelStore.shared.lookupModelID,
            available: ModelStore.shared.allAvailableModels)
        
        for item in items {
            let menuItem = NSMenuItem(
                title: item.title, action: #selector(selectLookupModel(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = item.modelID?.uuidString
            if item.isSelected {
                menuItem.state = .on
            }
            submenu.addItem(menuItem)
            
            // Keep the nil choice ("Same as Refine Model") visually apart from the models.
            if item.modelID == nil {
                submenu.addItem(.separator())
            }
        }
        
        return submenu
    }
    
    // Called by the system right before the menu is shown.
    func menuWillOpen(_ menu: NSMenu) {
        // Make sure everything (permission item + model checkmark) is up to date.
        refreshMenu()
    }
    
    @objc private func showFloatingBar() {
        NotificationCenter.default.post(name: AppDelegate.summonFloatingBarNotification, object: nil)
    }
    
    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let idString = sender.representedObject as? String,
              let uuid = UUID(uuidString: idString),
              let model = ModelStore.shared.allAvailableModels.first(where: { $0.id == uuid }) else { return }
        
        ModelStore.shared.selectModel(model)
    }
    
    @objc private func selectLookupModel(_ sender: NSMenuItem) {
        // nil means the "Same as Refine Model" item.
        guard let idString = sender.representedObject as? String else {
            ModelStore.shared.lookupModelID = nil
            return
        }
        guard let uuid = UUID(uuidString: idString),
              ModelStore.shared.allAvailableModels.contains(where: { $0.id == uuid })
        else { return }
        
        ModelStore.shared.lookupModelID = uuid
    }
    
    @objc private func openSettings() {
        NotificationCenter.default.post(name: .proprOpenSettings, object: nil)
    }

    @objc private func openManageModels() {
        NotificationCenter.default.post(
            name: .proprOpenSettings,
            object: nil,
            userInfo: ["selectSection": "models"]
        )
    }
    
    @objc private func openPermissions() {
        // For returning users we still want the real OnboardingView (it handles the
        // current permission state + "Start using Propr" button gracefully).
        AppDelegate.shared?.showOnboardingForPermissionRecovery()
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
