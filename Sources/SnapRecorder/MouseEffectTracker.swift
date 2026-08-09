import CoreGraphics
import CoreMedia
import Foundation

/// Polls public session mouse state on the capture queue, so the custom pointer
/// does not need Accessibility or Input Monitoring permission.
final class MouseEffectTracker {
    private let captureRect: CGRect
    private let clickDuration: Double = 0.65
    private var wasPressed = false
    private var clickBeganAt: Double?
    private var clickPosition: CGPoint?

    init(captureRect: CGRect) {
        self.captureRect = captureRect.standardized
        synchronizeButtonState()
    }

    func snapshot(at presentationTime: CMTime) -> MouseEffectSnapshot {
        let cursorPosition = currentNormalizedCursorPosition()
        let isPressed = Self.isAnyButtonPressed
        let currentTime = presentationTime.seconds

        if isPressed, !wasPressed, let cursorPosition, currentTime.isFinite {
            clickBeganAt = currentTime
            clickPosition = cursorPosition
        }
        wasPressed = isPressed

        var clickEffect: MouseClickEffect?
        if let clickBeganAt,
           let clickPosition,
           currentTime.isFinite {
            let progress = (currentTime - clickBeganAt) / clickDuration
            if progress >= 0, progress < 1 {
                clickEffect = MouseClickEffect(
                    normalizedPosition: clickPosition,
                    progress: CGFloat(progress)
                )
            } else if progress >= 1 {
                self.clickBeganAt = nil
                self.clickPosition = nil
            }
        }

        return MouseEffectSnapshot(
            normalizedCursorPosition: cursorPosition,
            clickEffect: clickEffect
        )
    }

    func didResume() {
        clickBeganAt = nil
        clickPosition = nil
        synchronizeButtonState()
    }

    private func currentNormalizedCursorPosition() -> CGPoint? {
        guard let location = CGEvent(source: nil)?.location else { return nil }
        return Self.normalizedPosition(for: location, in: captureRect)
    }

    static func normalizedPosition(for location: CGPoint, in rect: CGRect) -> CGPoint? {
        let captureRect = rect.standardized
        guard captureRect.width > 0,
              captureRect.height > 0,
              captureRect.contains(location) else { return nil }

        return CGPoint(
            x: min(max((location.x - captureRect.minX) / captureRect.width, 0), 1),
            y: min(max((location.y - captureRect.minY) / captureRect.height, 0), 1)
        )
    }

    private func synchronizeButtonState() {
        wasPressed = Self.isAnyButtonPressed
    }

    private static var isAnyButtonPressed: Bool {
        CGEventSource.buttonState(.combinedSessionState, button: .left)
            || CGEventSource.buttonState(.combinedSessionState, button: .right)
            || CGEventSource.buttonState(.combinedSessionState, button: .center)
    }
}
