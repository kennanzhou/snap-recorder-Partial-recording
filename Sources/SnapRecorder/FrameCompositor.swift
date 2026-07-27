import CoreGraphics
import CoreImage
import CoreVideo
import Foundation

final class FrameCompositor {
    private let mode: CaptureMode
    private let outputSize: CGSize
    private let context: CIContext
    private let colorSpace: CGColorSpace

    init(mode: CaptureMode, outputSize: CGSize) {
        self.mode = mode
        self.outputSize = outputSize
        self.context = CIContext(options: [
            .useSoftwareRenderer: false,
            .cacheIntermediates: false
        ])
        self.colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    }

    func render(source pixelBuffer: CVPixelBuffer, into destination: CVPixelBuffer) {
        let source = normalized(CIImage(cvPixelBuffer: pixelBuffer))
        let image: CIImage

        switch mode {
        case .display:
            image = displayComposition(source)
        case .browser:
            image = browserComposition(source)
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

    private func browserComposition(_ source: CIImage) -> CIImage {
        let background = CIImage(color: .black).cropped(to: canvasRect)
        return aspectFit(source, inside: canvasRect).composited(over: background)
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
