import Cocoa

// NSApplication.shared must be initialized BEFORE accessing NSApp globals
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = AppDelegate()
app.delegate = delegate
app.run()
