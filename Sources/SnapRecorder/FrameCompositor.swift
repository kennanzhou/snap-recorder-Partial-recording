import CoreGraphics
import CoreImage
import CoreVideo
import Foundation

/// 成片里的鼠标“准星”：白色细圆环 + 上下左右四道短刻线，外描一圈深色；点击时圆环向外扩散并淡出。
/// 数值为 1080p 画面上的像素，按画面短边等比缩放（0.65–2.25 倍）。
enum MouseEffectStyle {
    static let ringRadius: CGFloat = 12
    static let ringWidth: CGFloat = 2
    static let tickInner: CGFloat = 15
    static let tickOuter: CGFloat = 22
    static let tickWidth: CGFloat = 2
    static let outlineWidth: CGFloat = 1.25
    static let opacity: CGFloat = 0.95
    static let outlineOpacity: CGFloat = 0.6

    static func scale(for canvas: CGSize) -> CGFloat {
        min(2.25, max(0.65, min(canvas.width, canvas.height) / 1_080))
    }

    /// 点击扩散：半径从圆环放大到约 2.8 倍，线条略变粗，透明度逐渐降为 0。
    static func clickRadius(progress: CGFloat) -> CGFloat { ringRadius * (1 + 1.8 * progress) }
    static func clickLineWidth(progress: CGFloat) -> CGFloat { ringWidth * (1 + 0.6 * progress) }
    static func clickOpacity(progress: CGFloat) -> CGFloat { pow(1 - progress, 1.35) * 0.9 }
}

final class FrameCompositor {
    private let mode: CaptureMode
    private let outputSize: CGSize
    private let context: CIContext
    private let colorSpace: CGColorSpace
    private let captureCornerStyle: FocusMaskCornerStyle
    private let appliesSoftCornerVignette: Bool
    private let focusMask: CaptureFocusMask?
    private let cameraOverlayRenderer: CameraOverlayRenderer?

    init(
        mode: CaptureMode,
        outputSize: CGSize,
        captureCornerStyle: FocusMaskCornerStyle = .square,
        appliesSoftCornerVignette: Bool = false,
        focusMask: CaptureFocusMask? = nil,
        cameraOverlay: CameraOverlaySettings? = nil
    ) {
        self.mode = mode
        self.outputSize = outputSize
        self.captureCornerStyle = captureCornerStyle
        self.appliesSoftCornerVignette = appliesSoftCornerVignette
        self.focusMask = focusMask
        self.cameraOverlayRenderer = cameraOverlay.map {
            CameraOverlayRenderer(settings: $0, outputSize: outputSize)
        }
        self.context = CIContext(options: [
            .useSoftwareRenderer: false,
            .cacheIntermediates: false
        ])
        self.colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    }

    func render(
        source pixelBuffer: CVPixelBuffer,
        into destination: CVPixelBuffer,
        mouseEffect: MouseEffectSnapshot? = nil,
        cameraFrame: CameraFrame? = nil
    ) {
        let source = normalized(CIImage(cvPixelBuffer: pixelBuffer))
        var image: CIImage

        switch mode {
        case .display, .region:
            image = displayComposition(source)
        case .window:
            image = windowComposition(source)
        }

        if mode == .region, let focusMask {
            image = applyingFocusMask(focusMask, to: image)
        }
        if mode == .region, captureCornerStyle == .rounded {
            image = applyingCaptureCorners(
                to: image,
                feathered: appliesSoftCornerVignette
            )
        }
        if let mouseEffect {
            image = applyingMouseEffect(mouseEffect, to: image)
        }
        if let cameraFrame, let cameraOverlayRenderer {
            image = cameraOverlayRenderer.composite(cameraFrame.pixelBuffer, over: image)
        }

        context.render(
            image.cropped(to: canvasRect),
            to: destination,
            bounds: canvasRect,
            colorSpace: colorSpace
        )
    }

    private var canvasRect: CGRect {
        CGRect(origin: .zero, size: outputSize)
    }

    private func displayComposition(_ source: CIImage) -> CIImage {
        let background = CIImage(color: .black).cropped(to: canvasRect)
        return aspectFit(source, inside: canvasRect).composited(over: background)
    }

    private func windowComposition(_ source: CIImage) -> CIImage {
        let background = CIImage(color: .black).cropped(to: canvasRect)
        return aspectFit(source, inside: canvasRect).composited(over: background)
    }

    private func applyingFocusMask(
        _ focusMask: CaptureFocusMask,
        to image: CIImage
    ) -> CIImage {
        let normalized = focusMask.normalizedRect.standardized
        let focusRect = CGRect(
            x: min(max(normalized.minX, 0), 1) * canvasRect.width,
            y: min(max(normalized.minY, 0), 1) * canvasRect.height,
            width: min(max(normalized.width, 0), 1) * canvasRect.width,
            height: min(max(normalized.height, 0), 1) * canvasRect.height
        ).intersection(canvasRect)
        guard focusRect.width >= 2, focusRect.height >= 2 else { return image }

        let monochromeAndDimmed = image
            .applyingFilter(
                "CIColorControls",
                parameters: [kCIInputSaturationKey: 0]
            )
            .applyingFilter(
                "CIExposureAdjust",
                parameters: [kCIInputEVKey: -1]
            )
        let radius: CGFloat
        switch focusMask.cornerStyle {
        case .square:
            radius = 0
        case .rounded:
            radius = min(30, max(10, min(focusRect.width, focusRect.height) * 0.035))
        }
        guard let mask = roundedMask(in: focusRect, radius: radius) else {
            return image
        }
        return image.applyingFilter(
            "CIBlendWithAlphaMask",
            parameters: [
                kCIInputBackgroundImageKey: monochromeAndDimmed,
                kCIInputMaskImageKey: mask
            ]
        )
    }

    private func applyingCaptureCorners(
        to image: CIImage,
        feathered: Bool
    ) -> CIImage {
        let minimumDimension = min(canvasRect.width, canvasRect.height)
        let radius = min(52, max(18, minimumDimension * 0.04))
        let mask: CIImage
        if feathered {
            let feather = min(14, max(5, minimumDimension * 0.006))
            let extendedRect = canvasRect.insetBy(dx: -feather, dy: -feather)
            guard let baseMask = roundedMask(
                in: extendedRect,
                radius: radius + feather
            ) else { return image }
            mask = baseMask
                .applyingFilter(
                    "CIGaussianBlur",
                    parameters: [kCIInputRadiusKey: feather]
                )
                .cropped(to: canvasRect)
        } else {
            guard let baseMask = roundedMask(in: canvasRect, radius: radius) else {
                return image
            }
            mask = baseMask.cropped(to: canvasRect)
        }
        let black = CIImage(color: .black).cropped(to: canvasRect)
        return image.applyingFilter(
            "CIBlendWithAlphaMask",
            parameters: [
                kCIInputBackgroundImageKey: black,
                kCIInputMaskImageKey: mask
            ]
        )
    }

    private func applyingMouseEffect(
        _ snapshot: MouseEffectSnapshot,
        to image: CIImage
    ) -> CIImage {
        var result = image
        let scale = MouseEffectStyle.scale(for: canvasRect.size)
        let outline = MouseEffectStyle.outlineWidth * scale

        if let click = snapshot.clickEffect {
            let progress = min(max(click.progress, 0), 1)
            let center = canvasPoint(for: click.normalizedPosition)
            let radius = MouseEffectStyle.clickRadius(progress: progress) * scale
            let lineWidth = MouseEffectStyle.clickLineWidth(progress: progress) * scale
            let opacity = MouseEffectStyle.clickOpacity(progress: progress)

            if let shadowMask = crispRingMask(center: center, radius: radius, lineWidth: lineWidth + outline * 2) {
                result = coloredLayer(
                    color: CIColor(red: 0, green: 0, blue: 0, alpha: opacity * MouseEffectStyle.outlineOpacity),
                    mask: shadowMask
                ).composited(over: result)
            }
            if let ring = crispRingMask(center: center, radius: radius, lineWidth: lineWidth) {
                result = coloredLayer(
                    color: CIColor(red: 1, green: 1, blue: 1, alpha: opacity),
                    mask: ring
                ).composited(over: result)
            }
        }

        if let normalizedCursorPosition = snapshot.normalizedCursorPosition {
            let center = canvasPoint(for: normalizedCursorPosition)
            let radius = MouseEffectStyle.ringRadius * scale
            let lineWidth = MouseEffectStyle.ringWidth * scale
            let ticks = reticleTicks(center: center, scale: scale)

            // 深色外描先画，白色圆环与刻线压在上面，深浅画面上都看得清。
            let outlineColor = CIColor(red: 0, green: 0, blue: 0, alpha: MouseEffectStyle.outlineOpacity)
            if let ringOutline = crispRingMask(center: center, radius: radius, lineWidth: lineWidth + outline * 2) {
                result = coloredLayer(color: outlineColor, mask: ringOutline).composited(over: result)
            }
            result = coloredLayer(
                color: outlineColor,
                mask: rectanglesMask(ticks.map { $0.insetBy(dx: -outline, dy: -outline).integral })
            ).composited(over: result)

            let white = CIColor(red: 1, green: 1, blue: 1, alpha: MouseEffectStyle.opacity)
            if let ring = crispRingMask(center: center, radius: radius, lineWidth: lineWidth) {
                result = coloredLayer(color: white, mask: ring).composited(over: result)
            }
            result = coloredLayer(color: white, mask: rectanglesMask(ticks)).composited(over: result)
        }

        return result
    }

    /// 准星的四道短刻线：圆环外侧上下左右各一道，按像素取整，保持横平竖直。
    private func reticleTicks(center: CGPoint, scale: CGFloat) -> [CGRect] {
        let inner = MouseEffectStyle.tickInner * scale
        let outer = MouseEffectStyle.tickOuter * scale
        let width = max(1, (MouseEffectStyle.tickWidth * scale).rounded())
        let half = width / 2
        return [
            CGRect(x: center.x - outer, y: center.y - half, width: outer - inner, height: width),
            CGRect(x: center.x + inner, y: center.y - half, width: outer - inner, height: width),
            CGRect(x: center.x - half, y: center.y - outer, width: width, height: outer - inner),
            CGRect(x: center.x - half, y: center.y + inner, width: width, height: outer - inner)
        ].map { $0.integral }
    }

    /// 边缘只留约 1px 抗锯齿的圆环，线条清楚，不像光晕那样发虚。
    private func crispRingMask(center: CGPoint, radius: CGFloat, lineWidth: CGFloat) -> CIImage? {
        guard let outer = discMask(center: center, radius: radius + lineWidth / 2),
              let inner = discMask(center: center, radius: max(0, radius - lineWidth / 2)) else { return nil }
        return outer
            .applyingFilter("CISourceOutCompositing", parameters: [kCIInputBackgroundImageKey: inner])
            .cropped(to: canvasRect)
    }

    private func discMask(center: CGPoint, radius: CGFloat) -> CIImage? {
        radialMask(center: center, innerRadius: max(0, radius - 0.6), outerRadius: radius + 0.6)
    }

    private func rectanglesMask(_ rects: [CGRect]) -> CIImage {
        rects.reduce(CIImage(color: .clear).cropped(to: canvasRect)) { mask, rect in
            CIImage(color: .white).cropped(to: rect.intersection(canvasRect)).composited(over: mask)
        }
    }

    private func canvasPoint(for normalizedPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(normalizedPoint.x, 0), 1) * canvasRect.width,
            y: (1 - min(max(normalizedPoint.y, 0), 1)) * canvasRect.height
        )
    }

    private func radialMask(
        center: CGPoint,
        innerRadius: CGFloat,
        outerRadius: CGFloat
    ) -> CIImage? {
        guard outerRadius > innerRadius,
              let filter = CIFilter(name: "CIRadialGradient") else { return nil }
        filter.setValue(CIVector(cgPoint: center), forKey: kCIInputCenterKey)
        filter.setValue(innerRadius, forKey: "inputRadius0")
        filter.setValue(outerRadius, forKey: "inputRadius1")
        filter.setValue(CIColor.white, forKey: "inputColor0")
        filter.setValue(CIColor.clear, forKey: "inputColor1")
        return filter.outputImage?.cropped(to: canvasRect)
    }

    private func coloredLayer(color: CIColor, mask: CIImage) -> CIImage {
        let foreground = CIImage(color: color).cropped(to: canvasRect)
        let transparent = CIImage(color: .clear).cropped(to: canvasRect)
        return foreground.applyingFilter(
            "CIBlendWithAlphaMask",
            parameters: [
                kCIInputBackgroundImageKey: transparent,
                kCIInputMaskImageKey: mask
            ]
        )
    }

    private func roundedMask(in rect: CGRect, radius: CGFloat) -> CIImage? {
        if radius <= 0 {
            return CIImage(color: .white).cropped(to: rect)
        }
        guard let filter = CIFilter(name: "CIRoundedRectangleGenerator") else {
            return nil
        }
        filter.setValue(CIVector(cgRect: rect), forKey: "inputExtent")
        filter.setValue(radius, forKey: "inputRadius")
        filter.setValue(CIColor.white, forKey: kCIInputColorKey)
        return filter.outputImage
    }

    private func normalized(_ image: CIImage) -> CIImage {
        image.transformed(
            by: CGAffineTransform(
                translationX: -image.extent.minX,
                y: -image.extent.minY
            )
        )
    }

    private func aspectFit(
        _ image: CIImage,
        inside rect: CGRect,
        allowUpscale: Bool = true
    ) -> CIImage {
        let source = normalized(image)
        guard source.extent.width > 0, source.extent.height > 0 else { return source }
        let requestedScale = min(
            rect.width / source.extent.width,
            rect.height / source.extent.height
        )
        let scale = allowUpscale ? requestedScale : min(requestedScale, 1)
        let scaled = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let x = rect.midX - scaled.extent.width / 2
        let y = rect.midY - scaled.extent.height / 2
        return scaled.transformed(by: CGAffineTransform(translationX: x, y: y))
    }
}
