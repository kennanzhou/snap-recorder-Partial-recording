import AppKit
import CoreGraphics

@MainActor
final class CaptureRegionOverlayController {
    private var panel: NSPanel?
    private var overlayView: CaptureRegionOverlayView?
    private var screen: NSScreen?
    private var selectionChanged: ((CaptureRegion) -> Void)?
    private var focusMaskChanged: ((CaptureFocusMask?) -> Void)?

    var isVisible: Bool { panel?.isVisible == true }

    @discardableResult
    func show(
        aspectRatio: CaptureAspectRatio,
        captureCornerStyle: FocusMaskCornerStyle,
        focusMaskEnabled: Bool,
        focusMaskCornerStyle: FocusMaskCornerStyle,
        interactionLocked: Bool,
        selectionChanged: @escaping (CaptureRegion) -> Void,
        focusMaskChanged: @escaping (CaptureFocusMask?) -> Void
    ) -> CaptureRegion? {
        self.selectionChanged = selectionChanged
        self.focusMaskChanged = focusMaskChanged

        let targetScreen = Self.mainDisplayScreen() ?? NSScreen.main ?? NSScreen.screens.first
        guard let targetScreen else { return nil }
        screen = targetScreen

        let panel: NSPanel
        let overlayView: CaptureRegionOverlayView
        if let existingPanel = self.panel, let existingView = self.overlayView {
            panel = existingPanel
            overlayView = existingView
        } else {
            let initialFrame = Self.initialFrame(
                on: targetScreen,
                aspectRatio: aspectRatio.fixedValue ?? CaptureAspectRatio.widescreen.fixedValue!
            )
            let createdPanel = NSPanel(
                contentRect: initialFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            createdPanel.level = .floating
            createdPanel.isFloatingPanel = true
            createdPanel.hidesOnDeactivate = false
            createdPanel.becomesKeyOnlyIfNeeded = true
            createdPanel.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
                .stationary,
                .ignoresCycle
            ]
            createdPanel.backgroundColor = .clear
            createdPanel.isOpaque = false
            createdPanel.hasShadow = false
            createdPanel.sharingType = .none
            createdPanel.acceptsMouseMovedEvents = true

            let createdView = CaptureRegionOverlayView(frame: createdPanel.contentView?.bounds ?? .zero)
            createdView.autoresizingMask = [.width, .height]
            createdPanel.contentView = createdView
            createdView.frameChanged = { [weak self] frame in
                self?.publishSelection(for: frame)
            }
            createdView.focusMaskChanged = { [weak self] mask in
                self?.focusMaskChanged?(mask)
            }

            self.panel = createdPanel
            self.overlayView = createdView
            panel = createdPanel
            overlayView = createdView
        }

        overlayView.configure(
            panel: panel,
            screenFrame: targetScreen.frame,
            aspectRatio: aspectRatio,
            captureCornerStyle: captureCornerStyle,
            focusMaskEnabled: focusMaskEnabled,
            focusMaskCornerStyle: focusMaskCornerStyle
        )
        setInteractionLocked(interactionLocked)
        panel.orderFrontRegardless()
        publishSelection(for: panel.frame)
        focusMaskChanged(currentFocusMask)
        return currentRegion
    }

    @discardableResult
    func update(aspectRatio: CaptureAspectRatio) -> CaptureRegion? {
        guard let panel, let overlayView, let screen else { return nil }
        overlayView.configure(
            panel: panel,
            screenFrame: screen.frame,
            aspectRatio: aspectRatio,
            captureCornerStyle: overlayView.captureCornerStyle,
            focusMaskEnabled: overlayView.isFocusMaskEnabled,
            focusMaskCornerStyle: overlayView.focusMaskCornerStyle
        )
        if let fixedValue = aspectRatio.fixedValue {
            panel.setFrame(
                Self.frame(panel.frame, fittedTo: fixedValue, within: screen.frame),
                display: true
            )
        }
        overlayView.needsDisplay = true
        publishSelection(for: panel.frame)
        return currentRegion
    }

    @discardableResult
    func setFocusMaskEnabled(_ enabled: Bool) -> CaptureFocusMask? {
        guard let overlayView else { return nil }
        overlayView.setFocusMaskEnabled(enabled)
        let mask = currentFocusMask
        focusMaskChanged?(mask)
        return mask
    }

    @discardableResult
    func setFocusMaskCornerStyle(_ style: FocusMaskCornerStyle) -> CaptureFocusMask? {
        guard let overlayView else { return nil }
        overlayView.setFocusMaskCornerStyle(style)
        let mask = currentFocusMask
        focusMaskChanged?(mask)
        return mask
    }

    func setCaptureCornerStyle(_ style: FocusMaskCornerStyle) {
        overlayView?.setCaptureCornerStyle(style)
    }

    @discardableResult
    func setInteractionLocked(_ locked: Bool) -> Bool {
        guard let panel, let overlayView else { return false }
        panel.ignoresMouseEvents = locked
        overlayView.setInteractionLocked(locked)
        return locked
    }

    @discardableResult
    func toggleInteractionLocked() -> Bool {
        setInteractionLocked(!(overlayView?.isInteractionLocked ?? false))
    }

    func hide() {
        panel?.orderOut(nil)
    }

    var currentRegion: CaptureRegion? {
        guard let panel, let screen else { return nil }
        return Self.captureRegion(for: panel.frame, on: screen)
    }

    var currentFocusMask: CaptureFocusMask? {
        overlayView?.currentFocusMask
    }

    private func publishSelection(for frame: CGRect) {
        guard let screen,
              let region = Self.captureRegion(for: frame, on: screen) else { return }
        selectionChanged?(region)
    }

    private static func mainDisplayScreen() -> NSScreen? {
        let mainDisplayID = CGMainDisplayID()
        return NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber else { return false }
            return CGDirectDisplayID(number.uint32Value) == mainDisplayID
        }
    }

    private static func initialFrame(on screen: NSScreen, aspectRatio: CGFloat) -> CGRect {
        let bounds = screen.frame.insetBy(dx: 56, dy: 56)
        var width = bounds.width * 0.68
        var height = width / aspectRatio
        if height > bounds.height * 0.72 {
            height = bounds.height * 0.72
            width = height * aspectRatio
        }
        return CGRect(
            x: bounds.midX - width / 2,
            y: bounds.midY - height / 2,
            width: width,
            height: height
        ).integral
    }

    private static func frame(
        _ current: CGRect,
        fittedTo aspectRatio: CGFloat,
        within screenFrame: CGRect
    ) -> CGRect {
        let bounds = screenFrame.insetBy(dx: 10, dy: 10)
        let area = max(1, current.width * current.height)
        var width = sqrt(area * aspectRatio)
        var height = width / aspectRatio
        let scale = min(1, bounds.width / width, bounds.height / height)
        width *= scale
        height *= scale

        let center = CGPoint(
            x: min(max(current.midX, bounds.minX + width / 2), bounds.maxX - width / 2),
            y: min(max(current.midY, bounds.minY + height / 2), bounds.maxY - height / 2)
        )
        return CGRect(
            x: center.x - width / 2,
            y: center.y - height / 2,
            width: width,
            height: height
        ).integral
    }

    private static func captureRegion(for frame: CGRect, on screen: NSScreen) -> CaptureRegion? {
        guard let number = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber else { return nil }

        let clipped = frame.intersection(screen.frame)
        guard clipped.width >= 2, clipped.height >= 2 else { return nil }
        let localRect = CGRect(
            x: clipped.minX - screen.frame.minX,
            y: screen.frame.maxY - clipped.maxY,
            width: clipped.width,
            height: clipped.height
        ).integral
        return CaptureRegion(
            displayID: CGDirectDisplayID(number.uint32Value),
            sourceRect: localRect
        )
    }
}

private final class CaptureRegionOverlayView: NSView {
    private enum DragOperation {
        case move
        case resize(ResizeHandle)
        case moveFocus
        case resizeFocus(ResizeHandle)
    }

    private struct ResizeHandle {
        let horizontal: CGFloat
        let vertical: CGFloat
    }

    weak var panel: NSPanel?
    var frameChanged: ((CGRect) -> Void)?
    var focusMaskChanged: ((CaptureFocusMask?) -> Void)?

    private var screenFrame = CGRect.zero
    private var aspectRatio: CGFloat?
    private var ratioTitle = "16:9"
    private(set) var captureCornerStyle: FocusMaskCornerStyle = .rounded
    private(set) var isFocusMaskEnabled = false
    private(set) var focusMaskCornerStyle: FocusMaskCornerStyle = .rounded
    private(set) var isInteractionLocked = false
    private var normalizedFocusRect = CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
    private var dragOperation: DragOperation?
    private var dragStartFrame = CGRect.zero
    private var dragStartMouse = CGPoint.zero
    private var dragStartFocusRect = CGRect.zero
    private var dragStartLocalMouse = CGPoint.zero
    private var trackingAreaReference: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    func configure(
        panel: NSPanel,
        screenFrame: CGRect,
        aspectRatio: CaptureAspectRatio,
        captureCornerStyle: FocusMaskCornerStyle,
        focusMaskEnabled: Bool,
        focusMaskCornerStyle: FocusMaskCornerStyle
    ) {
        self.panel = panel
        self.screenFrame = screenFrame.insetBy(dx: 10, dy: 10)
        self.aspectRatio = aspectRatio.fixedValue
        ratioTitle = aspectRatio.title
        self.captureCornerStyle = captureCornerStyle
        isFocusMaskEnabled = focusMaskEnabled && aspectRatio.fixedValue != nil
        self.focusMaskCornerStyle = focusMaskCornerStyle
        needsDisplay = true
    }

    var currentFocusMask: CaptureFocusMask? {
        guard isFocusMaskEnabled else { return nil }
        return CaptureFocusMask(
            normalizedRect: normalizedFocusRect,
            cornerStyle: focusMaskCornerStyle
        )
    }

    func setFocusMaskEnabled(_ enabled: Bool) {
        isFocusMaskEnabled = enabled && aspectRatio != nil
        needsDisplay = true
    }

    func setFocusMaskCornerStyle(_ style: FocusMaskCornerStyle) {
        focusMaskCornerStyle = style
        needsDisplay = true
    }

    func setCaptureCornerStyle(_ style: FocusMaskCornerStyle) {
        captureCornerStyle = style
        needsDisplay = true
    }

    func setInteractionLocked(_ locked: Bool) {
        isInteractionLocked = locked
        needsDisplay = true
        if !locked {
            NSCursor.openHand.set()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaReference = trackingArea
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if isFocusMaskEnabled, let handle = focusResizeHandle(at: point) {
            if handle.horizontal == 0 {
                NSCursor.resizeUpDown.set()
            } else if handle.vertical == 0 {
                NSCursor.resizeLeftRight.set()
            } else {
                NSCursor.crosshair.set()
            }
            return
        }
        if isFocusMaskEnabled, focusRect.contains(point) {
            NSCursor.openHand.set()
            return
        }
        if let handle = resizeHandle(at: point) {
            if handle.horizontal == 0 {
                NSCursor.resizeUpDown.set()
            } else if handle.vertical == 0 {
                NSCursor.resizeLeftRight.set()
            } else {
                NSCursor.crosshair.set()
            }
        } else {
            NSCursor.openHand.set()
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let panel else { return }
        let point = convert(event.locationInWindow, from: nil)
        if isFocusMaskEnabled, let handle = focusResizeHandle(at: point) {
            dragOperation = .resizeFocus(handle)
        } else if isFocusMaskEnabled, focusRect.contains(point) {
            dragOperation = .moveFocus
        } else {
            dragOperation = resizeHandle(at: point).map(DragOperation.resize) ?? .move
        }
        dragStartFrame = panel.frame
        dragStartMouse = NSEvent.mouseLocation
        dragStartFocusRect = focusRect
        dragStartLocalMouse = point
        if case .move = dragOperation {
            NSCursor.closedHand.set()
        } else if case .moveFocus = dragOperation {
            NSCursor.closedHand.set()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let panel, let dragOperation else { return }
        let mouse = NSEvent.mouseLocation
        let nextFrame: CGRect
        switch dragOperation {
        case .move:
            let delta = CGPoint(
                x: mouse.x - dragStartMouse.x,
                y: mouse.y - dragStartMouse.y
            )
            nextFrame = constrainedMove(
                CGRect(
                    x: dragStartFrame.minX + delta.x,
                    y: dragStartFrame.minY + delta.y,
                    width: dragStartFrame.width,
                    height: dragStartFrame.height
                )
            )
        case .resize(let handle):
            nextFrame = resizedFrame(to: mouse, handle: handle)
        case .moveFocus:
            moveFocus(to: convert(event.locationInWindow, from: nil))
            return
        case .resizeFocus(let handle):
            resizeFocus(to: convert(event.locationInWindow, from: nil), handle: handle)
            return
        }
        panel.setFrame(nextFrame.integral, display: true)
        needsDisplay = true
        frameChanged?(panel.frame)
    }

    override func mouseUp(with event: NSEvent) {
        dragOperation = nil
        mouseMoved(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard bounds.width > 8, bounds.height > 8 else { return }

        if isFocusMaskEnabled {
            drawFocusMask()
        }

        let borderRect = bounds.insetBy(dx: 3, dy: 3)
        let border = captureCornerStyle == .rounded
            ? NSBezierPath(roundedRect: borderRect, xRadius: 12, yRadius: 12)
            : NSBezierPath(rect: borderRect)
        border.lineWidth = 5
        NSColor.systemPurple.withAlphaComponent(0.22).setStroke()
        border.stroke()

        border.lineWidth = 2
        border.setLineDash([8, 6], count: 2, phase: 0)
        NSColor.systemPink.withAlphaComponent(0.96).setStroke()
        border.stroke()

        drawHandles()
        drawRatioBadge()
    }

    private var focusBounds: CGRect {
        bounds.insetBy(dx: min(24, bounds.width * 0.08), dy: min(24, bounds.height * 0.08))
    }

    private var focusRect: CGRect {
        CGRect(
            x: bounds.width * normalizedFocusRect.minX,
            y: bounds.height * normalizedFocusRect.minY,
            width: bounds.width * normalizedFocusRect.width,
            height: bounds.height * normalizedFocusRect.height
        )
    }

    private func focusResizeHandle(at point: CGPoint) -> ResizeHandle? {
        let rect = focusRect
        let threshold: CGFloat = 12
        guard rect.insetBy(dx: -threshold, dy: -threshold).contains(point) else { return nil }
        let nearLeft = abs(point.x - rect.minX) <= threshold
        let nearRight = abs(point.x - rect.maxX) <= threshold
        let nearBottom = abs(point.y - rect.minY) <= threshold
        let nearTop = abs(point.y - rect.maxY) <= threshold
        let horizontal: CGFloat = nearLeft ? -1 : (nearRight ? 1 : 0)
        let vertical: CGFloat = nearBottom ? -1 : (nearTop ? 1 : 0)
        guard horizontal != 0 || vertical != 0 else { return nil }
        return ResizeHandle(horizontal: horizontal, vertical: vertical)
    }

    private func moveFocus(to point: CGPoint) {
        let delta = CGPoint(
            x: point.x - dragStartLocalMouse.x,
            y: point.y - dragStartLocalMouse.y
        )
        let allowed = focusBounds
        let moved = CGRect(
            x: min(
                max(dragStartFocusRect.minX + delta.x, allowed.minX),
                allowed.maxX - dragStartFocusRect.width
            ),
            y: min(
                max(dragStartFocusRect.minY + delta.y, allowed.minY),
                allowed.maxY - dragStartFocusRect.height
            ),
            width: dragStartFocusRect.width,
            height: dragStartFocusRect.height
        )
        setFocusRect(moved)
    }

    private func resizeFocus(to point: CGPoint, handle: ResizeHandle) {
        let allowed = focusBounds
        let minimumWidth: CGFloat = 84
        let minimumHeight: CGFloat = 64
        var minX = dragStartFocusRect.minX
        var maxX = dragStartFocusRect.maxX
        var minY = dragStartFocusRect.minY
        var maxY = dragStartFocusRect.maxY

        if handle.horizontal < 0 {
            minX = min(max(point.x, allowed.minX), maxX - minimumWidth)
        } else if handle.horizontal > 0 {
            maxX = max(min(point.x, allowed.maxX), minX + minimumWidth)
        }
        if handle.vertical < 0 {
            minY = min(max(point.y, allowed.minY), maxY - minimumHeight)
        } else if handle.vertical > 0 {
            maxY = max(min(point.y, allowed.maxY), minY + minimumHeight)
        }
        setFocusRect(CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
    }

    private func setFocusRect(_ rect: CGRect) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        normalizedFocusRect = CGRect(
            x: rect.minX / bounds.width,
            y: rect.minY / bounds.height,
            width: rect.width / bounds.width,
            height: rect.height / bounds.height
        )
        needsDisplay = true
        focusMaskChanged?(currentFocusMask)
    }

    private func drawFocusMask() {
        let rect = focusRect
        let cornerRadius: CGFloat = focusMaskCornerStyle == .rounded ? 12 : 0
        let dimmedArea = NSBezierPath(rect: bounds.insetBy(dx: 4, dy: 4))
        dimmedArea.appendRoundedRect(rect, xRadius: cornerRadius, yRadius: cornerRadius)
        dimmedArea.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.5).setFill()
        dimmedArea.fill()

        let outline = NSBezierPath(
            roundedRect: rect,
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )
        outline.lineWidth = 1.2
        NSColor(calibratedWhite: 0.56, alpha: 0.72).setStroke()
        outline.stroke()

        let handles = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY)
        ]
        for point in handles {
            let path = NSBezierPath(ovalIn: CGRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7))
            NSColor(calibratedWhite: 0.72, alpha: 0.88).setFill()
            path.fill()
        }
    }

    private func resizeHandle(at point: CGPoint) -> ResizeHandle? {
        let threshold: CGFloat = 18
        let nearLeft = point.x <= threshold
        let nearRight = point.x >= bounds.width - threshold
        let nearBottom = point.y <= threshold
        let nearTop = point.y >= bounds.height - threshold
        let horizontal: CGFloat = nearLeft ? -1 : (nearRight ? 1 : 0)
        let vertical: CGFloat = nearBottom ? -1 : (nearTop ? 1 : 0)

        guard horizontal != 0 || vertical != 0 else { return nil }
        if aspectRatio != nil, horizontal == 0 || vertical == 0 {
            return nil
        }
        return ResizeHandle(horizontal: horizontal, vertical: vertical)
    }

    private func constrainedMove(_ frame: CGRect) -> CGRect {
        CGRect(
            x: min(max(frame.minX, screenFrame.minX), screenFrame.maxX - frame.width),
            y: min(max(frame.minY, screenFrame.minY), screenFrame.maxY - frame.height),
            width: frame.width,
            height: frame.height
        )
    }

    private func resizedFrame(to mouse: CGPoint, handle: ResizeHandle) -> CGRect {
        if let aspectRatio {
            return fixedRatioFrame(to: mouse, handle: handle, ratio: aspectRatio)
        }
        return customRatioFrame(to: mouse, handle: handle)
    }

    private func customRatioFrame(to mouse: CGPoint, handle: ResizeHandle) -> CGRect {
        let minimumWidth: CGFloat = 160
        let minimumHeight: CGFloat = 100
        var minX = dragStartFrame.minX
        var maxX = dragStartFrame.maxX
        var minY = dragStartFrame.minY
        var maxY = dragStartFrame.maxY

        if handle.horizontal < 0 {
            minX = min(max(mouse.x, screenFrame.minX), maxX - minimumWidth)
        } else if handle.horizontal > 0 {
            maxX = max(min(mouse.x, screenFrame.maxX), minX + minimumWidth)
        }
        if handle.vertical < 0 {
            minY = min(max(mouse.y, screenFrame.minY), maxY - minimumHeight)
        } else if handle.vertical > 0 {
            maxY = max(min(mouse.y, screenFrame.maxY), minY + minimumHeight)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func fixedRatioFrame(
        to mouse: CGPoint,
        handle: ResizeHandle,
        ratio: CGFloat
    ) -> CGRect {
        let anchor = CGPoint(
            x: handle.horizontal < 0 ? dragStartFrame.maxX : dragStartFrame.minX,
            y: handle.vertical < 0 ? dragStartFrame.maxY : dragStartFrame.minY
        )
        let maximumWidth = handle.horizontal < 0
            ? anchor.x - screenFrame.minX
            : screenFrame.maxX - anchor.x
        let maximumHeight = handle.vertical < 0
            ? anchor.y - screenFrame.minY
            : screenFrame.maxY - anchor.y
        let minimumWidth = max(160, 100 * ratio)
        var width = max(minimumWidth, abs(mouse.x - anchor.x))
        var height = max(100, abs(mouse.y - anchor.y))

        if width / height > ratio {
            height = width / ratio
        } else {
            width = height * ratio
        }

        let scale = min(1, maximumWidth / width, maximumHeight / height)
        width *= scale
        height *= scale

        return CGRect(
            x: handle.horizontal < 0 ? anchor.x - width : anchor.x,
            y: handle.vertical < 0 ? anchor.y - height : anchor.y,
            width: width,
            height: height
        )
    }

    private func drawHandles() {
        var points = [
            CGPoint(x: 4, y: 4),
            CGPoint(x: bounds.maxX - 4, y: 4),
            CGPoint(x: 4, y: bounds.maxY - 4),
            CGPoint(x: bounds.maxX - 4, y: bounds.maxY - 4)
        ]
        if aspectRatio == nil {
            points += [
                CGPoint(x: bounds.midX, y: 4),
                CGPoint(x: bounds.midX, y: bounds.maxY - 4),
                CGPoint(x: 4, y: bounds.midY),
                CGPoint(x: bounds.maxX - 4, y: bounds.midY)
            ]
        }

        for point in points {
            let handleRect = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
            let handle = NSBezierPath(ovalIn: handleRect)
            NSColor.white.setFill()
            handle.fill()
            handle.lineWidth = 1.5
            NSColor.systemPink.setStroke()
            handle.stroke()
        }
    }

    private func drawRatioBadge() {
        let instruction: String
        if isInteractionLocked {
            instruction = "浮层已锁定 · ⌘E 调整"
        } else if isFocusMaskEnabled {
            instruction = "拖动内框聚焦 · ⌘E 锁定"
        } else {
            instruction = "拖动框内移动 · ⌘E 锁定"
        }
        let text = "\(ratioTitle)  ·  \(instruction)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.92)
        ]
        let textSize = text.size(withAttributes: attributes)
        let badgeRect = CGRect(
            x: bounds.midX - (textSize.width + 22) / 2,
            y: bounds.maxY - textSize.height - 20,
            width: textSize.width + 22,
            height: textSize.height + 10
        )
        let badge = NSBezierPath(roundedRect: badgeRect, xRadius: badgeRect.height / 2, yRadius: badgeRect.height / 2)
        NSColor(calibratedWhite: 0.06, alpha: 0.82).setFill()
        badge.fill()
        NSColor.white.withAlphaComponent(0.13).setStroke()
        badge.lineWidth = 1
        badge.stroke()
        text.draw(
            at: CGPoint(x: badgeRect.minX + 11, y: badgeRect.minY + 5),
            withAttributes: attributes
        )
    }
}
