import AppKit
import AVFoundation
import SwiftUI

@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    private weak var model: AppModel?
    private var mainWindow: NSWindow?
    private var countdownPanel: NSPanel?
    private var recordingPanel: NSPanel?
    private var statusItem: NSStatusItem?
    private var lastExternalApplication: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?
    private let regionOverlay = CaptureRegionOverlayController()
    private var shortcutController: GlobalShortcutController?
    private let cameraPreview = CameraPreviewController()

    init(initialExternalApplication: NSRunningApplication?) {
        lastExternalApplication = initialExternalApplication
        super.init()

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                  application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
                return
            }
            Task { @MainActor [weak self] in
                self?.lastExternalApplication = application
            }
        }
    }

    deinit {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
    }

    func attach(model: AppModel) {
        self.model = model
        shortcutController = GlobalShortcutController(
            toggleOverlay: { [weak model] in
                Task { @MainActor in model?.toggleRegionSelectionLock() }
            },
            startRecording: { [weak model] in
                Task { @MainActor in model?.startRecordingFromShortcut() }
            },
            stopRecording: { [weak model] in
                Task { @MainActor in model?.stopRecording() }
            }
        )
        createStatusItemIfNeeded()
    }

    var mainWindowID: CGWindowID? {
        guard let mainWindow, mainWindow.windowNumber > 0 else { return nil }
        return CGWindowID(mainWindow.windowNumber)
    }

    func showMainWindow() {
        guard let model else { return }
        let window: NSWindow

        if let mainWindow {
            window = mainWindow
        } else {
            let created = Self.makeMainWindow()
            created.delegate = self
            created.contentViewController = NSHostingController(
                rootView: RecorderView(model: model)
            )
            created.center()
            mainWindow = created
            window = created
        }

        statusItem?.isVisible = true
        restoreInteractiveMainWindowLevel()
        window.hidesOnDeactivate = false
        // Accessory apps can lose the ordering race when another normal-level
        // app (usually the selected browser) is still active. LaunchServices
        // can also restore that app after applicationDidFinishLaunching, so
        // confirm the same one-time ordering action on the next run-loop turn.
        bringMainWindowForward(window)
        Self.installTitlebarDragSurface(on: window)
        Task { @MainActor [weak self, weak window] in
            // App activation is asynchronous. A short delayed confirmation
            // avoids LaunchServices returning focus to the previously active
            // browser after a cold launch or reopen request.
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, let window, self.mainWindow === window,
                  window.isVisible, self.model?.phase != .countdown else { return }
            self.bringMainWindowForward(window)
        }
    }

    private func bringMainWindowForward(_ window: NSWindow) {
        NSApp.activate()
        // The persistent interactive level is managed separately; these calls
        // only make the currently requested main window active and frontmost.
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }

    /// Also used by the camera-free pointer-interaction test harness.
    static func makeMainWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 510),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Snap Recorder"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // SwiftUI controls can leave mouse-down handling to a drag gesture.
        // Background window dragging steals that sequence before the slider
        // starts tracking. Only the native title bar may initiate window moves.
        window.isMovableByWindowBackground = false
        window.isMovable = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        // The main panel is ordinary, shareable content. Auxiliary windows stay
        // excluded by the capture filter, including ones created after capture starts.
        window.sharingType = .readOnly
        return window
    }

    private static func installTitlebarDragSurface(on window: NSWindow) {
        guard let frameView = window.contentView?.superview,
              !frameView.subviews.contains(where: { $0 is TitlebarDragSurface }) else { return }
        let dragSurface = TitlebarDragSurface(frame: .zero)
        // AppKit skips a fully transparent layer in the private title-bar hit
        // hierarchy. A 0.1% neutral fill keeps the hit plane composited while
        // remaining visually indistinguishable from transparent.
        dragSurface.wantsLayer = true
        dragSurface.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.001).cgColor
        frameView.addSubview(dragSurface, positioned: .above, relativeTo: nil)
    }

    @discardableResult
    func showRegionSelection(
        aspectRatio: CaptureAspectRatio,
        captureCornerStyle: FocusMaskCornerStyle,
        focusMaskEnabled: Bool,
        focusMaskCornerStyle: FocusMaskCornerStyle,
        interactionLocked: Bool,
        selectionChanged: @escaping (CaptureRegion) -> Void,
        focusMaskChanged: @escaping (CaptureFocusMask?) -> Void
    ) -> CaptureRegion? {
        mainWindow?.level = .screenSaver
        return regionOverlay.show(
            aspectRatio: aspectRatio,
            captureCornerStyle: captureCornerStyle,
            focusMaskEnabled: focusMaskEnabled,
            focusMaskCornerStyle: focusMaskCornerStyle,
            interactionLocked: interactionLocked,
            selectionChanged: selectionChanged,
            focusMaskChanged: focusMaskChanged
        )
    }

    @discardableResult
    func updateRegionAspectRatio(_ aspectRatio: CaptureAspectRatio) -> CaptureRegion? {
        regionOverlay.update(aspectRatio: aspectRatio)
    }

    @discardableResult
    func setRegionFocusMaskEnabled(_ enabled: Bool) -> CaptureFocusMask? {
        regionOverlay.setFocusMaskEnabled(enabled)
    }

    @discardableResult
    func setRegionFocusMaskCornerStyle(_ style: FocusMaskCornerStyle) -> CaptureFocusMask? {
        regionOverlay.setFocusMaskCornerStyle(style)
    }

    func setRegionCaptureCornerStyle(_ style: FocusMaskCornerStyle) {
        regionOverlay.setCaptureCornerStyle(style)
    }

    @discardableResult
    func setRegionSelectionLocked(_ locked: Bool) -> Bool {
        regionOverlay.setInteractionLocked(locked)
    }

    @discardableResult
    func toggleRegionSelectionLocked() -> Bool {
        regionOverlay.toggleInteractionLocked()
    }

    func updateGlobalShortcuts(
        isRegionPreparing: Bool,
        isRegionLocked: Bool,
        isCountdownActive: Bool = false,
        isRecording: Bool
    ) {
        shortcutController?.update(
            isRegionPreparing: isRegionPreparing,
            isRegionLocked: isRegionLocked,
            isCountdownActive: isCountdownActive,
            isRecording: isRecording
        )
    }

    func hideRegionSelection(resetMainWindowLevel: Bool = false) {
        regionOverlay.hide()
        if resetMainWindowLevel {
            restoreInteractiveMainWindowLevel()
        }
    }

    private func restoreInteractiveMainWindowLevel() {
        guard let model else { return }
        // The setup/export window must remain reachable while the user still
        // has work to do. It is ordered out before countdown, so floating here
        // never makes it part of the recording workflow.
        mainWindow?.level = model.mode == .region ? .screenSaver : .floating
    }

    func prepareForCountdown(targetProcessID: pid_t?) {
        mainWindow?.orderOut(nil)
        statusItem?.isVisible = false

        let targetApplication = targetProcessID.flatMap(NSRunningApplication.init(processIdentifier:))
            ?? lastExternalApplication
        targetApplication?.activate(options: [.activateAllWindows])
    }

    func runCountdown(from start: Int) async throws {
        let panel = countdownPanel ?? makeCountdownPanel()
        countdownPanel = panel
        position(panel: panel, size: CGSize(width: 174, height: 174), topOffset: nil)
        defer { panel.orderOut(nil) }

        for number in stride(from: start, through: 1, by: -1) {
            try Task.checkCancellation()
            panel.contentView = NSHostingView(rootView: CountdownView(number: number))
            panel.orderFrontRegardless()
            try await Task.sleep(for: .seconds(1))
        }
    }

    func showRecordingHUD() {
        guard let model else { return }
        statusItem?.isVisible = true
        let panel: NSPanel

        if let recordingPanel {
            panel = recordingPanel
        } else {
            let created = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 274, height: 54),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            created.level = .screenSaver
            created.isFloatingPanel = true
            created.hidesOnDeactivate = false
            created.becomesKeyOnlyIfNeeded = true
            created.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
                .stationary,
                .ignoresCycle
            ]
            created.backgroundColor = .clear
            created.isOpaque = false
            created.hasShadow = true
            created.sharingType = .none
            created.contentView = NSHostingView(rootView: RecordingHUDView(model: model))
            recordingPanel = created
            panel = created
        }

        position(panel: panel, size: CGSize(width: 274, height: 54), topOffset: 18)
        panel.orderFrontRegardless()
        // 局部录像时选区浮层保持显示；控制条出现即进入录制态，刻度转为信号橙。
        regionOverlay.setRecordingActive(true)
    }

    func hideRecordingHUD() {
        recordingPanel?.orderOut(nil)
        regionOverlay.setRecordingActive(false)
    }

    func showCameraPreview(frames: CameraFrameStore, settings: CameraOverlaySettings) {
        cameraPreview.show(frames: frames, settings: settings)
    }

    func hideCameraPreview() {
        cameraPreview.hide()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === mainWindow else { return true }

        // A user-initiated close is an explicit quit request. Keep the window
        // alive until AppDelegate has applied the recording/export safeguards;
        // idle sessions terminate immediately, while protected states can
        // cancel without leaving an invisible menu-bar process behind.
        NSApp.terminate(nil)
        return false
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === mainWindow {
            model?.mainWindowClosed()
        }
    }

    private func makeCountdownPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 174, height: 174),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.sharingType = .none
        return panel
    }

    private func position(panel: NSPanel, size: CGSize, topOffset: CGFloat?) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let frame = screen.visibleFrame
        let origin: CGPoint

        if let topOffset {
            origin = CGPoint(
                x: frame.midX - size.width / 2,
                y: frame.maxY - size.height - topOffset
            )
        } else {
            origin = CGPoint(
                x: frame.midX - size.width / 2,
                y: frame.midY - size.height / 2
            )
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func createStatusItemIfNeeded() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "record.circle",
            accessibilityDescription: "Snap Recorder 录屏"
        )

        let menu = NSMenu()
        let openItem = NSMenuItem(
            title: "打开 Snap Recorder",
            action: #selector(openSnapRecorder),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: "退出 Snap Recorder",
            action: #selector(quitSnapRecorder),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        item.menu = menu
        statusItem = item
    }

    @objc private func openSnapRecorder() {
        showMainWindow()
    }

    @objc private func quitSnapRecorder() {
        NSApp.terminate(nil)
    }
}

/// A native AppKit hit target installed above the full-size SwiftUI host view.
/// It occupies only the intentionally empty title-bar strip to avoid stealing
/// gestures from traffic lights or recorder controls.
private final class TitlebarDragSurface: NSView {
    private static let height: CGFloat = 44
    private static let leading: CGFloat = 76
    private var dragStartMouseLocation: NSPoint?
    private var dragStartWindowOrigin: NSPoint?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            self?.alignToHostTop()
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        guard event.clickCount == 1, window?.isMovable == true else {
            super.mouseDown(with: event)
            return
        }
        dragStartMouseLocation = NSEvent.mouseLocation
        dragStartWindowOrigin = window?.frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let dragStartMouseLocation, let dragStartWindowOrigin else {
            super.mouseDragged(with: event)
            return
        }
        let mouseLocation = NSEvent.mouseLocation
        window.setFrameOrigin(
            NSPoint(
                x: dragStartWindowOrigin.x + mouseLocation.x - dragStartMouseLocation.x,
                y: dragStartWindowOrigin.y + mouseLocation.y - dragStartMouseLocation.y
            )
        )
    }

    override func mouseUp(with event: NSEvent) {
        dragStartMouseLocation = nil
        dragStartWindowOrigin = nil
    }

    private func alignToHostTop() {
        guard let superview else { return }
        let topY = superview.isFlipped ? 0 : superview.bounds.height - Self.height
        frame = NSRect(
            x: Self.leading,
            y: topY,
            width: max(0, superview.bounds.width - Self.leading),
            height: Self.height
        )
        autoresizingMask = superview.isFlipped
            ? [.width, .maxYMargin]
            : [.width, .minYMargin]
    }
}
