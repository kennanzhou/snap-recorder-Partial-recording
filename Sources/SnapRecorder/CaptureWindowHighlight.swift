import AppKit
import CoreGraphics
import ScreenCaptureKit

/// A click-through, non-shareable outline that identifies the independently
/// captured window without modifying the target application.
@MainActor
final class CaptureWindowHighlightController {
    private static let inset: CGFloat = 12
    private var panel: NSPanel?
    private var trackedWindowID: CGWindowID?
    private var trackingTimer: Timer?
    private var cornerDetectionGeneration = UUID()

    func show(windowID: CGWindowID, fallbackFrame: CGRect) {
        trackedWindowID = windowID
        let detectionGeneration = UUID()
        cornerDetectionGeneration = detectionGeneration
        let panel = panel ?? makePanel()
        self.panel = panel
        (panel.contentView as? CaptureWindowHighlightView)?.cornerRadius = 12
        updatePanelFrame(using: currentFrame(for: windowID) ?? fallbackFrame)
        panel.orderFrontRegardless()
        startTracking()

        Task { @MainActor [weak self] in
            guard let radius = await Self.detectCornerRadius(
                windowID: windowID,
                fallbackFrame: fallbackFrame
            ), let self,
            self.cornerDetectionGeneration == detectionGeneration,
            self.trackedWindowID == windowID else { return }
            (self.panel?.contentView as? CaptureWindowHighlightView)?.cornerRadius = radius
        }
    }

    func hide() {
        trackedWindowID = nil
        cornerDetectionGeneration = UUID()
        trackingTimer?.invalidate()
        trackingTimer = nil
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.sharingType = .none

        let outline = CaptureWindowHighlightView(frame: .zero)
        outline.autoresizingMask = [.width, .height]
        panel.contentView = outline
        return panel
    }

    private func startTracking() {
        trackingTimer?.invalidate()
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let windowID = self.trackedWindowID else { return }
                guard let frame = self.currentFrame(for: windowID) else {
                    self.panel?.orderOut(nil)
                    return
                }
                self.updatePanelFrame(using: frame)
                if self.panel?.isVisible != true {
                    self.panel?.orderFrontRegardless()
                }
            }
        }
    }

    private func updatePanelFrame(using quartzFrame: CGRect) {
        guard quartzFrame.width > 1, quartzFrame.height > 1 else { return }
        let targetFrame = Self.appKitFrame(from: quartzFrame)
            .insetBy(dx: -Self.inset, dy: -Self.inset)
            .integral
        panel?.setFrame(targetFrame, display: true)
    }

    private func currentFrame(for windowID: CGWindowID) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionIncludingWindow],
            windowID
        ) as? [[String: Any]],
        let bounds = list.first?[kCGWindowBounds as String] as? [String: Any] else {
            return nil
        }
        return CGRect(dictionaryRepresentation: bounds as CFDictionary)
    }

    private static func appKitFrame(from quartzFrame: CGRect) -> CGRect {
        let desktopTop = NSScreen.screens.first?.frame.maxY ?? quartzFrame.maxY
        return CGRect(
            x: quartzFrame.minX,
            y: desktopTop - quartzFrame.maxY,
            width: quartzFrame.width,
            height: quartzFrame.height
        )
    }

    /// ScreenCaptureKit does not expose a window-corner-radius property. Take
    /// one shadow-free, in-memory snapshot of the selected window and read only
    /// the alpha transition at its four corners. The image is never retained or
    /// written to disk.
    private static func detectCornerRadius(
        windowID: CGWindowID,
        fallbackFrame: CGRect
    ) async -> CGFloat? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                true,
                onScreenWindowsOnly: true
            )
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                return nil
            }

            let pointSize = window.frame.size == .zero ? fallbackFrame.size : window.frame.size
            guard pointSize.width > 1, pointSize.height > 1 else { return nil }
            let sampleScale = min(1, 1_024 / max(pointSize.width, pointSize.height))

            let configuration = SCStreamConfiguration()
            configuration.width = max(2, Int((pointSize.width * sampleScale).rounded()))
            configuration.height = max(2, Int((pointSize.height * sampleScale).rounded()))
            configuration.captureResolution = .best
            configuration.ignoreShadowsSingleWindow = true
            configuration.shouldBeOpaque = false

            let filter = SCContentFilter(desktopIndependentWindow: window)
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            return measuredCornerRadius(of: image, pointSize: pointSize)
        } catch {
            return nil
        }
    }

    private static func measuredCornerRadius(
        of image: CGImage,
        pointSize: CGSize
    ) -> CGFloat? {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return nil
        default:
            break
        }

        let width = image.width
        let height = image.height
        guard width > 2, height > 2 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drewImage = pixels.withUnsafeMutableBytes { memory -> Bool in
            guard let context = CGContext(
                data: memory.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drewImage else { return nil }

        let alphaThreshold: UInt8 = 32
        let maximumX = min(width / 3, max(2, Int(32 * CGFloat(width) / pointSize.width)))
        let maximumY = min(height / 3, max(2, Int(32 * CGFloat(height) / pointSize.height)))
        let scaleX = CGFloat(width) / pointSize.width
        let scaleY = CGFloat(height) / pointSize.height

        func alpha(x: Int, y: Int) -> UInt8 {
            pixels[((y * width) + x) * 4 + 3]
        }
        func firstOpaque(limit: Int, sample: (Int) -> UInt8) -> Int? {
            (0...limit).first { sample($0) > alphaThreshold }
        }

        let horizontalDistances = [
            firstOpaque(limit: maximumX) { alpha(x: $0, y: 0) },
            firstOpaque(limit: maximumX) { alpha(x: width - 1 - $0, y: 0) },
            firstOpaque(limit: maximumX) { alpha(x: $0, y: height - 1) },
            firstOpaque(limit: maximumX) { alpha(x: width - 1 - $0, y: height - 1) }
        ].compactMap { $0 }.map { CGFloat($0) / scaleX }
        let verticalDistances = [
            firstOpaque(limit: maximumY) { alpha(x: 0, y: $0) },
            firstOpaque(limit: maximumY) { alpha(x: width - 1, y: $0) },
            firstOpaque(limit: maximumY) { alpha(x: 0, y: height - 1 - $0) },
            firstOpaque(limit: maximumY) { alpha(x: width - 1, y: height - 1 - $0) }
        ].compactMap { $0 }.map { CGFloat($0) / scaleY }

        let distances = (horizontalDistances + verticalDistances).sorted()
        guard !distances.isEmpty else { return nil }
        let median = distances[distances.count / 2]
        return min(28, max(0, median.rounded()))
    }
}

private final class CaptureWindowHighlightView: NSView {
    var cornerRadius: CGFloat = 12 {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSGraphicsContext.saveGraphicsState()

        let frame = bounds.insetBy(dx: 12, dy: 12)
        let path = NSBezierPath(
            roundedRect: frame,
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )
        path.lineWidth = 3

        let glow = NSShadow()
        glow.shadowColor = NSColor(hex: 0xEE5A24, alpha: 0.65)
        glow.shadowBlurRadius = 10
        glow.shadowOffset = .zero
        glow.set()

        NSColor(hex: 0xEE5A24).setStroke()
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()

        NSColor(hex: 0xB8430F, alpha: 0.7).setStroke()
        let innerPath = NSBezierPath(
            roundedRect: frame.insetBy(dx: 1, dy: 1),
            xRadius: max(0, cornerRadius - 1),
            yRadius: max(0, cornerRadius - 1)
        )
        innerPath.lineWidth = 1
        innerPath.stroke()
    }
}
