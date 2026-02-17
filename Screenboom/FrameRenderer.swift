import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import AppKit

enum FrameRenderer {
    struct Settings: @unchecked Sendable {
        var padding: CGFloat
        var cornerRadius: CGFloat
        var shadowRadius: CGFloat
        var shadowOpacity: CGFloat
        var gradientColor1: NSColor
        var gradientColor2: NSColor
        var outputSize: CGSize
    }

    nonisolated static func makeVideoComposition(
        for asset: AVAsset,
        sourceSize: CGSize,
        settings: Settings,
        cursorOverlayState: CursorOverlayState? = nil
    ) -> AVMutableVideoComposition {
        let outputSize = settings.outputSize
        let outputRect = CGRect(origin: .zero, size: outputSize)

        // Calculate recording rect (centered with padding)
        let recordingRect = calculateRecordingRect(
            sourceSize: sourceSize,
            outputSize: outputSize,
            padding: settings.padding
        )

        // Pre-compute static images
        let maskImage = createRoundedRectMask(
            outputSize: outputSize,
            rect: recordingRect,
            cornerRadius: settings.cornerRadius
        )

        let shadowImage = createShadow(
            maskImage: maskImage,
            outputSize: outputSize,
            radius: settings.shadowRadius,
            opacity: settings.shadowOpacity
        )

        let backgroundImage = createGradient(
            color1: CIColor(color: settings.gradientColor1) ?? CIColor.black,
            color2: CIColor(color: settings.gradientColor2) ?? CIColor.black,
            size: outputSize
        )

        let ciContext = CIContext(options: [
            .useSoftwareRenderer: false,
            .highQualityDownsample: true,
            .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        ])
        let clearImage = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0))
            .cropped(to: outputRect)

        // Capture values for the Sendable closure
        let recRect = recordingRect
        let cursorState = cursorOverlayState

        let videoComposition = AVMutableVideoComposition(asset: asset, applyingCIFiltersWithHandler: { request in
            let sourceExtent = request.sourceImage.extent

            // Auto-zoom: crop source to a smaller region before scaling
            var sourceImage = request.sourceImage
            var effectiveExtent = sourceExtent
            var activeZoomCrop: CGRect?

            if let cursorState {
                let frameTime = request.compositionTime.seconds
                if let cropRect = CursorOverlayEngine.zoomCropRect(
                    in: cursorState,
                    at: frameTime,
                    sourceExtent: sourceExtent
                ) {
                    sourceImage = sourceImage.cropped(to: cropRect)
                    effectiveExtent = sourceImage.extent
                    activeZoomCrop = cropRect
                }
            }

            // Scale source to fit recording area — Lanczos for sharp screen content
            let scaleX = recRect.width / effectiveExtent.width
            let scaleY = recRect.height / effectiveExtent.height
            let scale = min(scaleX, scaleY)

            let lanczos = CIFilter.lanczosScaleTransform()
            lanczos.inputImage = sourceImage
            lanczos.scale = Float(scale)
            lanczos.aspectRatio = 1.0
            let scaled = lanczos.outputImage ?? sourceImage

            let scaledExtent = scaled.extent
            let offsetX = recRect.midX - scaledExtent.width / 2 - scaledExtent.origin.x
            let offsetY = recRect.midY - scaledExtent.height / 2 - scaledExtent.origin.y

            let positioned = scaled
                .transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))
                .cropped(to: recRect)

            // Apply rounded corners via mask
            let rounded = positioned
                .applyingFilter("CIBlendWithMask", parameters: [
                    kCIInputBackgroundImageKey: clearImage,
                    kCIInputMaskImageKey: maskImage
                ])

            // Cursor + click effect overlay
            var withCursor = rounded
            if let cursorState {
                let frameTime = request.compositionTime.seconds
                if let cursorComposite = CursorOverlayEngine.cursorComposite(
                    in: cursorState,
                    at: frameTime,
                    recordingRect: recRect,
                    outputSize: outputSize,
                    zoomCropRect: activeZoomCrop
                ) {
                    withCursor = cursorComposite.composited(over: withCursor)
                }
            }

            // Composite: recording over shadow over background
            let result = withCursor
                .composited(over: shadowImage)
                .composited(over: backgroundImage)
                .cropped(to: outputRect)

            request.finish(with: result, context: ciContext)
        })

        videoComposition.renderSize = outputSize

        // Match source frame rate to avoid jitter from frame dropping
        let sourceRate: Float
        if let track = asset.tracks(withMediaType: .video).first {
            sourceRate = track.nominalFrameRate > 0 ? track.nominalFrameRate : 30
        } else {
            sourceRate = 30
        }
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(sourceRate))

        return videoComposition
    }

    // MARK: - Helpers

    nonisolated private static func calculateRecordingRect(
        sourceSize: CGSize,
        outputSize: CGSize,
        padding: CGFloat
    ) -> CGRect {
        let availW = outputSize.width - 2 * padding
        let availH = outputSize.height - 2 * padding
        guard availW > 0, availH > 0 else {
            return CGRect(origin: .zero, size: outputSize)
        }

        let scaleX = availW / sourceSize.width
        let scaleY = availH / sourceSize.height
        let scale = min(scaleX, scaleY)

        let w = sourceSize.width * scale
        let h = sourceSize.height * scale
        let x = (outputSize.width - w) / 2
        let y = (outputSize.height - h) / 2

        return CGRect(x: x, y: y, width: w, height: h)
    }

    nonisolated private static func createRoundedRectMask(
        outputSize: CGSize,
        rect: CGRect,
        cornerRadius: CGFloat
    ) -> CIImage {
        let w = Int(outputSize.width)
        let h = Int(outputSize.height)

        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return CIImage(color: .white).cropped(to: CGRect(origin: .zero, size: outputSize))
        }

        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(origin: .zero, size: outputSize))

        ctx.setFillColor(gray: 1, alpha: 1)
        let path = CGPath(
            roundedRect: rect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        ctx.addPath(path)
        ctx.fillPath()

        guard let cgImage = ctx.makeImage() else {
            return CIImage(color: .white).cropped(to: CGRect(origin: .zero, size: outputSize))
        }

        return CIImage(cgImage: cgImage)
    }

    nonisolated private static func createShadow(
        maskImage: CIImage,
        outputSize: CGSize,
        radius: CGFloat,
        opacity: CGFloat
    ) -> CIImage {
        guard opacity > 0, radius > 0 else {
            return CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0))
                .cropped(to: CGRect(origin: .zero, size: outputSize))
        }

        // Offset mask down for shadow
        let offset = maskImage
            .transformed(by: CGAffineTransform(translationX: 0, y: -8))

        // Blur
        let blurred = offset
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])

        // Convert to black shadow with alpha from mask brightness
        let shadow = blurred
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: opacity, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
            ])
            .cropped(to: CGRect(origin: .zero, size: outputSize))

        return shadow
    }

    nonisolated private static func createGradient(
        color1: CIColor,
        color2: CIColor,
        size: CGSize
    ) -> CIImage {
        let filter = CIFilter.linearGradient()
        filter.point0 = CGPoint(x: 0, y: size.height)
        filter.point1 = CGPoint(x: size.width, y: 0)
        filter.color0 = color1
        filter.color1 = color2

        return filter.outputImage!.cropped(to: CGRect(origin: .zero, size: size))
    }
}
