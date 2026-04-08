import Cocoa
import SwiftUI
import UserNotifications
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let dataManager = DataManager()
    private var eventMonitor: Any?
    private var updateTimer: Timer?
    private var settingsWindow: NSWindow?
    private var helpWindow: NSWindow?
    private var updaterController: SPUStandardUpdaterController?

    // MARK: - Bear Animation
    private var bearFrame = 0
    private var textTick  = 0   // 0.5s 타이머 기준, 2틱마다(=1s) 가격 텍스트 갱신

    static func applyAppearance() {
        switch AppSettings.shared.appearanceMode {
        case .system: NSApp.appearance = nil
        case .light:  NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.applyAppearance()
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        setupMainMenu()
        setupStatusItem()
        setupPopover()
        dataManager.startAutoRefresh()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        // 0.5초마다 호출: 곰 프레임 업데이트 + 1초마다 가격 텍스트 갱신
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.bearFrame = (self.bearFrame + 1) % 8  // 8프레임 루프
            self.textTick  += 1
            self.updateStatusButton(forceText: self.textTick % 2 == 0)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        updateTimer?.invalidate()
    }

    // MARK: - Main Menu (⌘V 등 단축키 활성화)

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu (최소한 필요)
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        // Edit menu — 이게 있어야 ⌘V / ⌘C / ⌘X / ⌘A 작동
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut",        action: #selector(NSText.cut(_:)),       keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy",       action: #selector(NSText.copy(_:)),      keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste",      action: #selector(NSText.paste(_:)),     keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "\(AppSettings.shared.iconEmoji) --"
        statusItem.button?.action = #selector(handleStatusItemClick)
        statusItem.button?.target = self
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func updateStatusButton(forceText: Bool = true) {
        guard let button = statusItem.button else { return }

        // 곰 아이콘 애니메이션
        button.image = makeBearFrame(bearFrame)
        button.imagePosition = .imageLeft

        // 가격 텍스트 (1초마다 갱신)
        if forceText {
            let icon  = AppSettings.shared.iconEmoji + " "
            let full  = dataManager.statusBarText
            // 이미지로 곰을 표시하므로 텍스트에서 emoji 접두사 제거
            let text  = full.hasPrefix(icon) ? String(full.dropFirst(icon.count)) : full
            let color: NSColor = {
                switch dataManager.statusBarColor {
                case .green:   return .systemGreen
                case .red:     return .systemRed
                case .primary: return .labelColor
                }
            }()
            button.attributedTitle = NSAttributedString(
                string: text,
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                    .foregroundColor: color
                ]
            )
        }
    }

    // MARK: - 이모지 아이콘 애니메이션 (설정 아이콘 이모지를 위아래로 통통)

    private func makeBearFrame(_ frame: Int) -> NSImage {
        let emoji = AppSettings.shared.iconEmoji
        let sz: CGFloat = 18
        // 사인파 형태의 위아래 bob: 8프레임 → 부드러운 바운스
        let bobs: [CGFloat] = [0, 0.6, 1.2, 0.6, 0, -0.6, -1.2, -0.6]
        let yOff = bobs[frame % 8]

        let img = NSImage(size: NSSize(width: sz, height: sz))
        img.lockFocus()
        let font = NSFont.systemFont(ofSize: 14)
        let attr = NSAttributedString(string: emoji, attributes: [.font: font])
        let strSz = attr.size()
        attr.draw(at: NSPoint(
            x: (sz - strSz.width)  / 2,
            y: (sz - strSz.height) / 2 + yOff
        ))
        img.unlockFocus()
        img.isTemplate = false
        return img
    }

    // MARK: - Popover

    private func setupPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        let hc = NSHostingController(
            rootView: StatusMenuView(dataManager: dataManager, openSettings: { [weak self] in
                self?.openSettingsWindow()
            })
        )
        hc.sizingOptions = .preferredContentSize  // 콘텐츠 크기에 맞게 팝오버 자동 조절
        popover.contentViewController = hc
    }

    @objc private func handleStatusItemClick() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp { showContextMenu() }
        else { togglePopover() }
    }

    private func togglePopover() {
        if popover.isShown { closePopover() }
        else { openPopover() }
    }

    private func openPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let update = NSMenuItem(title: "업데이트 확인...", action: #selector(checkForUpdates), keyEquivalent: "")
        update.target = self
        menu.addItem(update)

        menu.addItem(.separator())

        let refresh = NSMenuItem(title: "새로고침", action: #selector(refreshData), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let settings = NSMenuItem(title: "설정", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let help = NSMenuItem(title: "도움말", action: #selector(showHelp), keyEquivalent: "")
        help.target = self
        menu.addItem(help)

        menu.addItem(.separator())

        let about = NSMenuItem(title: "앱 정보", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func showHelp() {
        closePopover()
        if helpWindow == nil {
            let hosting = NSHostingController(rootView: HelpView())
            let window = NSWindow(contentViewController: hosting)
            window.title = "DigBar 도움말"
            window.setContentSize(NSSize(width: 560, height: 600))
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.minSize = NSSize(width: 480, height: 400)
            window.center()
            window.isReleasedWhenClosed = false
            window.delegate = self
            helpWindow = window
        }
        helpWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Settings Window (별도 창으로 열어야 ⌘V 등이 정상 동작)

    func openSettingsWindow() {
        closePopover()

        if settingsWindow == nil {
            let view = SettingsView(dataManager: dataManager)
            let hosting = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hosting)
            window.title = "DigBar 설정"
            window.setContentSize(NSSize(width: 540, height: 480))
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.minSize = NSSize(width: 480, height: 400)
            window.center()
            window.isReleasedWhenClosed = false
            window.delegate = self
            settingsWindow = window
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openSettings() { openSettingsWindow() }
    @objc private func refreshData() { Task { await dataManager.refreshAll() } }

    @objc private func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === settingsWindow {
            dataManager.stopAutoRefresh()
            dataManager.startAutoRefresh()
        }
        if (notification.object as? NSWindow) === helpWindow {
            helpWindow = nil
        }
    }
}
