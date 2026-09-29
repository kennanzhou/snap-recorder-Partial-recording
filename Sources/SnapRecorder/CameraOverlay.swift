import CoreGraphics
import CoreImage
import CoreVideo
import Foundation

enum CameraOverlayPosition: String, CaseIterable, Identifiable {
    case bottomRight
    case bottomLeft
    case topRight
    case topLeft

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bottomRight: "右下角"
        case .bottomLeft: "左下角"
        case .topRight: "右上角"
        case .topLeft: "左上角"
        }
    }
}

enum CameraOverlayShape: String, CaseIterable, Identifiable {
    case rounded
    case circle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rounded: "圆角"
        case .circle: "圆形"
        }
    }
}

enum CameraOverlaySize: String, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: "小"
        case .medium: "中"
        case .large: "大"
        }
    }

    var fraction: CGFloat {
        switch self {
        case .small: 0.18
        case .medium: 0.24
        case .large: 0.32
        }
    }
}

struct CameraOverlaySettings: Equatable {
    var position: CameraOverlayPosition = .bottomRight
    var shape: CameraOverlayShape = .rounded
    var size: CameraOverlaySize = .medium
    var mirrored = true
    var portrait = CameraPortraitSettings()

    /// Core Image coordinates, measured from the bottom-left of the final video.
    func rect(in outputSize: CGSize) -> CGRect {
        guard outputSize.width.isFinite, outputSize.height.isFinite,
              outputSize.width > 0, outputSize.height > 0 else { return .zero }
        let shortSide = min(outputSize.width, outputSize.height)
        let margin = shortSide * 0.035
        let side = shortSide * size.fraction
        let x: CGFloat
        let y: CGFloat
        switch position {
        case .bottomRight, .topRight:
            x = outputSize.width - margin - side
        case .bottomLeft, .topLeft:
            x = margin
        }
        switch position {
        case .bottomRight, .bottomLeft:
            y = margin
        case .topRight, .topLeft:
            y = outputSize.height - margin - side
        }
        return CGRect(x: x, y: y, width: side, height: side)
    }

    func cornerRadius(for rect: CGRect) -> CGFloat {
        min(rect.width, rect.height) * (shape == .circle ? 0.5 : 0.22)
    }

    /// 铝质边框宽度：边长的 3%，预览与成片按同一比例绘制。
    static func frameWidth(for rect: CGRect) -> CGFloat {
        max(1.5, min(rect.width, rect.height) * 0.03)
    }

    /// 边框外圈的深色细线，让铝框在浅色画面上也有轮廓。
    static func hairlineWidth(for rect: CGRect) -> CGFloat {
        max(0.75, min(rect.width, rect.height) * 0.004)
    }
}

/// 人像铝框的配色：自上而下由铝亮过渡到铝暗，外圈 40% 深色细线。
enum CameraFrameStyle {
    static let top = CIColor(red: 0xE6 / 255.0, green: 0xE4 / 255.0, blue: 0xDF / 255.0)
    static let bottom = CIColor(red: 0xC6 / 255.0, green: 0xC4 / 255.0, blue: 0xBE / 255.0)
    static let hairline = CIColor(red: 0, green: 0, blue: 0, alpha: 0.4)
}

/// The camera image is composed directly into the video. The floating preview
/// is deliberately separate, so it cannot be captured a second time.
final class CameraOverlayRenderer {
    private let settings: CameraOverlaySettings
    private let canvas: CGRect
    private let rect: CGRect
    private let cameraRect: CGRect
    private let mask: CIImage
    private let cameraMask: CIImage
    private let frame: CIImage
    private let hairline: CIImage
    private let shadow: CIImage

    init(settings: CameraOverlaySettings, outputSize: CGSize) {
        self.settings = settings
        canvas = CGRect(origin: .zero, size: outputSize)
        rect = settings.rect(in: outputSize)
        let radius = settings.cornerRadius(for: rect)
        mask = Self.roundedMask(rect: rect, radius: radius)

        // 铝框占据人像外缘，摄像头画面缩进一圈，圆角与外框同心。
        let frameWidth = CameraOverlaySettings.frameWidth(for: rect)
        cameraRect = rect.insetBy(dx: frameWidth, dy: frameWidth)
        cameraMask = Self.roundedMask(rect: cameraRect, radius: max(0, radius - frameWidth))
        frame = Self.verticalGradient(in: rect).cropped(to: canvas).applyingFilter(
            "CIBlendWithAlphaMask",
            parameters: [
                kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: canvas),
                kCIInputMaskImageKey: mask
            ]
        )

        let hairlineWidth = CameraOverlaySettings.hairlineWidth(for: rect)
        let outerMask = Self.roundedMask(
            rect: rect.insetBy(dx: -hairlineWidth, dy: -hairlineWidth),
            radius: radius + hairlineWidth
        )
        hairline = Self.coloredLayer(
            CameraFrameStyle.hairline,
            mask: outerMask.applyingFilter(
                "CISourceOutCompositing",
                parameters: [kCIInputBackgroundImageKey: mask]
            ),
            canvas: canvas
        )
        let shadowMask = mask
            .transformed(by: CGAffineTransform(translationX: 0, y: -rect.width * 0.025))
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: rect.width * 0.045])
        shadow = Self.coloredLayer(
            CIColor(red: 0, green: 0, blue: 0, alpha: 0.30),
            mask: shadowMask,
            canvas: canvas
        )
    }

    func composite(_ pixelBuffer: CVPixelBuffer, over background: CIImage) -> CIImage {
        var camera = CIImage(cvPixelBuffer: pixelBuffer)
        camera = camera.transformed(by: CGAffineTransform(
            translationX: -camera.extent.minX,
            y: -camera.extent.minY
        ))
        guard rect.width > 0, rect.height > 0,
              camera.extent.width > 0, camera.extent.height > 0 else { return background }
        if settings.mirrored {
            camera = camera.transformed(by: CGAffineTransform(
                a: -1, b: 0, c: 0, d: 1, tx: camera.extent.width, ty: 0
            ))
        }
        let scale = max(cameraRect.width / camera.extent.width, cameraRect.height / camera.extent.height)
        camera = camera.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        camera = camera.transformed(by: CGAffineTransform(
            translationX: cameraRect.midX - camera.extent.midX,
            y: cameraRect.midY - camera.extent.midY
        )).cropped(to: cameraRect)

        let withFrame = frame.composited(over: hairline.composited(over: shadow.composited(over: background)))
        return camera.applyingFilter(
            "CIBlendWithAlphaMask",
            parameters: [
                kCIInputBackgroundImageKey: withFrame,
                kCIInputMaskImageKey: cameraMask
            ]
        ).cropped(to: canvas)
    }

    private static func verticalGradient(in rect: CGRect) -> CIImage {
        guard let filter = CIFilter(name: "CILinearGradient") else {
            return CIImage(color: CameraFrameStyle.bottom)
        }
        filter.setValue(CIVector(x: rect.midX, y: rect.maxY), forKey: "inputPoint0")
        filter.setValue(CIVector(x: rect.midX, y: rect.minY), forKey: "inputPoint1")
        filter.setValue(CameraFrameStyle.top, forKey: "inputColor0")
        filter.setValue(CameraFrameStyle.bottom, forKey: "inputColor1")
        return filter.outputImage ?? CIImage(color: CameraFrameStyle.bottom)
    }

    private static func roundedMask(rect: CGRect, radius: CGFloat) -> CIImage {
        guard let filter = CIFilter(name: "CIRoundedRectangleGenerator") else {
            return CIImage(color: .white).cropped(to: rect)
        }
        filter.setValue(CIVector(cgRect: rect), forKey: "inputExtent")
        filter.setValue(radius, forKey: "inputRadius")
        filter.setValue(CIColor.white, forKey: kCIInputColorKey)
        return filter.outputImage ?? CIImage(color: .white).cropped(to: rect)
    }

    private static func coloredLayer(_ color: CIColor, mask: CIImage, canvas: CGRect) -> CIImage {
        CIImage(color: color).cropped(to: canvas).applyingFilter(
            "CIBlendWithAlphaMask",
            parameters: [
                kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: canvas),
                kCIInputMaskImageKey: mask
            ]
        )
    }
}
