import AppKit

// MusicTools — native macOS shell around the music-tools Flask app.
// This file boots NSApplication, installs a minimal menu (so Cmd-Q and
// copy/paste work inside the web view), and hands off to AppDelegate.

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let delegate = AppDelegate()
app.delegate = delegate

// ---- Minimal main menu --------------------------------------------------
// Without an Edit menu, the standard copy/paste/select-all responders are
// not wired up, which is noticeable inside a WKWebView (e.g. copying console
// output). This is the smallest menu that keeps those working.
func buildMainMenu() -> NSMenu {
    let mainMenu = NSMenu()

    let appItem = NSMenuItem()
    mainMenu.addItem(appItem)
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "About MusicTools",
                    action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                    keyEquivalent: "")
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: "Quit MusicTools",
                    action: #selector(NSApplication.terminate(_:)),
                    keyEquivalent: "q")
    appItem.submenu = appMenu

    let editItem = NSMenuItem()
    mainMenu.addItem(editItem)
    let editMenu = NSMenu(title: "Edit")
    editMenu.addItem(withTitle: "Undo",       action: Selector(("undo:")),            keyEquivalent: "z")
    editMenu.addItem(withTitle: "Redo",       action: Selector(("redo:")),            keyEquivalent: "Z")
    editMenu.addItem(.separator())
    editMenu.addItem(withTitle: "Cut",        action: #selector(NSText.cut(_:)),       keyEquivalent: "x")
    editMenu.addItem(withTitle: "Copy",       action: #selector(NSText.copy(_:)),      keyEquivalent: "c")
    editMenu.addItem(withTitle: "Paste",      action: #selector(NSText.paste(_:)),     keyEquivalent: "v")
    editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editItem.submenu = editMenu

    return mainMenu
}

app.mainMenu = buildMainMenu()
app.run()
