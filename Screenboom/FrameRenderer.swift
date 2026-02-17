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
        var backgroundStyle: BackgroundType
        var frameStyle: FrameStyle
        var outputSize: CGSize

        // Backward-compat convenience init for existing callers (tests, etc.)
        init(padding: CGFloat, cornerRadius: CGFloat, shadowRadius: CGFloat, shadowOpacity: CGFloat,
             gradientColor1: NSColor, gradientColor2: NSColor, outputSize: CGSize) {
            self.padding = padding
            self.cornerRadius = cornerRadius
            self.shadowRadius = shadowRadius
            self.shadowOpacity = shadowOpacity
            self.backgroundStyle = .gradient(CodableColor(nsColor: gradientColor1), CodableColor(nsColor: gradientColor2))
            self.frameStyle = .none
            self.outputSize = outputSize
        }

        init(padding: CGFloat, cornerRadius: CGFloat, shadowRadius: CGFloat, shadowOpacity: CGFloat,
             backgroundStyle: BackgroundType, frameStyle: FrameStyle, outputSize: CGSize) {
            self.padding = padding
            self.cornerRadius = cornerRadius
            self.shadowRadius = shadowRadius
            self.shadowOpacity = shadowOpacity
            self.backgroundStyle = backgroundStyle
            self.frameStyle = frameStyle
            self.outputSize = outputSize
        }
    }

    /// Scale factor for chrome/frame drawing. Reference design is 1080p.
    nonisolated static func pointScale(for outputSize: CGSize) -> CGFloat {
        outputSize.height / 1080.0
    }

    nonisolated static func makeVideoComposition(
        for asset: AVAsset,
        sourceSize: CGSize,
        settings: Settings,
        cursorOverlayState: CursorOverlayState? = nil,
        cachedBackgroundImage: CIImage? = nil
    ) -> AVMutableVideoComposition {
        let outputSize = settings.outputSize
        let outputRect = CGRect(origin: .zero, size: outputSize)
        let scale = pointScale(for: outputSize)
        let chromeH = settings.frameStyle.chromeHeight * scale

        // Calculate recording rect (centered with padding, reduced by chrome height)
        let recordingRect = calculateRecordingRect(
            sourceSize: sourceSize,
            outputSize: outputSize,
            padding: settings.padding,
            chromeHeight: chromeH
        )

        // Pre-compute mask — for chrome frames, union chrome rect + video rect
        let maskImage: CIImage
        if chromeH > 0 {
            maskImage = createChromeMask(
                outputSize: outputSize,
                recordingRect: recordingRect,
                chromeHeight: chromeH,
                cornerRadius: settings.cornerRadius
            )
        } else {
            maskImage = createRoundedRectMask(
                outputSize: outputSize,
                rect: recordingRect,
                cornerRadius: settings.cornerRadius
            )
        }

        let shadowImage = createShadow(
            maskImage: maskImage,
            outputSize: outputSize,
            radius: settings.shadowRadius,
            opacity: settings.shadowOpacity
        )

        let backgroundImage = cachedBackgroundImage ?? createBackground(
            style: settings.backgroundStyle,
            size: outputSize
        )

        let frameImage = createFrameOverlay(
            style: settings.frameStyle,
            rect: recordingRect,
            chromeHeight: chromeH,
            cornerRadius: settings.cornerRadius,
            outputSize: outputSize,
            pointScale: scale
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

            // Frame overlay (border, glow, chrome)
            var withFrame = withCursor
            if let frameOverlay = frameImage {
                withFrame = frameOverlay.composited(over: withFrame)
            }

            // Composite: recording over shadow over background
            let result = withFrame
                .composited(over: shadowImage)
                .composited(over: backgroundImage)
                .cropped(to: outputRect)

            request.finish(with: result, context: ciContext)
        })

        videoComposition.renderSize = outputSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 60)

        return videoComposition
    }

    // MARK: - Recording Rect

    nonisolated static func calculateRecordingRect(
        sourceSize: CGSize,
        outputSize: CGSize,
        padding: CGFloat,
        chromeHeight: CGFloat = 0
    ) -> CGRect {
        let availW = outputSize.width - 2 * padding
        let availH = outputSize.height - 2 * padding - chromeHeight
        guard availW > 0, availH > 0 else {
            return CGRect(origin: .zero, size: outputSize)
        }

        let scaleX = availW / sourceSize.width
        let scaleY = availH / sourceSize.height
        let scale = min(scaleX, scaleY)

        let w = sourceSize.width * scale
        let h = sourceSize.height * scale
        let x = (outputSize.width - w) / 2
        // Center vertically within the remaining space below chrome
        let y = padding + (availH - h) / 2

        return CGRect(x: x, y: y, width: w, height: h)
    }

    // MARK: - Background

    nonisolated static func createBackground(style: BackgroundType, size: CGSize) -> CIImage {
        let resolved = style.resolved()
        let rect = CGRect(origin: .zero, size: size)

        switch resolved {
        case .solid(let color):
            return CIImage(color: color.toCIColor()).cropped(to: rect)

        case .gradient(let c1, let c2):
            let filter = CIFilter.linearGradient()
            filter.point0 = CGPoint(x: 0, y: size.height)
            filter.point1 = CGPoint(x: size.width, y: 0)
            filter.color0 = c1.toCIColor()
            filter.color1 = c2.toCIColor()
            return filter.outputImage!.cropped(to: rect)

        case .mesh(let tl, let tr, let bl, let br):
            return createMeshBackground(topLeft: tl, topRight: tr, bottomLeft: bl, bottomRight: br, size: size)

        case .wallpaper:
            // Should already be resolved
            return CIImage(color: CIColor.black).cropped(to: rect)

        case .image(let bookmarkData):
            return createImageBackground(bookmarkData: bookmarkData, size: size)
        }
    }

    private nonisolated static func createMeshBackground(
        topLeft: CodableColor, topRight: CodableColor,
        bottomLeft: CodableColor, bottomRight: CodableColor,
        size: CGSize
    ) -> CIImage {
        let w = Int(size.width)
        let h = Int(size.height)
        guard w > 0, h > 0 else {
            return CIImage(color: CIColor.black).cropped(to: CGRect(origin: .zero, size: size))
        }

        // Downsample for performance — render at 1/4 res then upscale
        let scale = 4
        let sw = max(1, w / scale)
        let sh = max(1, h / scale)

        guard let ctx = CGContext(
            data: nil, width: sw, height: sh,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return CIImage(color: CIColor.black).cropped(to: CGRect(origin: .zero, size: size))
        }

        // Bilinear interpolation of 4 corners
        // CGContext has bottom-left origin: row 0 = bottom.
        // topLeft/topRight → row sh-1, bottomLeft/bottomRight → row 0
        for row in 0..<sh {
            let fy = Double(row) / Double(max(1, sh - 1))  // 0 = bottom, 1 = top
            for col in 0..<sw {
                let fx = Double(col) / Double(max(1, sw - 1))

                let r = (1 - fx) * (1 - fy) * bottomLeft.red + fx * (1 - fy) * bottomRight.red +
                        (1 - fx) * fy * topLeft.red + fx * fy * topRight.red
                let g = (1 - fx) * (1 - fy) * bottomLeft.green + fx * (1 - fy) * bottomRight.green +
                        (1 - fx) * fy * topLeft.green + fx * fy * topRight.green
                let b = (1 - fx) * (1 - fy) * bottomLeft.blue + fx * (1 - fy) * bottomRight.blue +
                        (1 - fx) * fy * topLeft.blue + fx * fy * topRight.blue

                ctx.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1.0))
                ctx.fill(CGRect(x: col, y: row, width: 1, height: 1))
            }
        }

        guard let cgImage = ctx.makeImage() else {
            return CIImage(color: CIColor.black).cropped(to: CGRect(origin: .zero, size: size))
        }

        // Upscale with Lanczos
        let ciSmall = CIImage(cgImage: cgImage)
        let lanczos = CIFilter.lanczosScaleTransform()
        lanczos.inputImage = ciSmall
        lanczos.scale = Float(scale)
        lanczos.aspectRatio = 1.0
        if let upscaled = lanczos.outputImage {
            return upscaled.cropped(to: CGRect(origin: .zero, size: size))
        }
        return ciSmall
    }

    private nonisolated static func createImageBackground(bookmarkData: Data, size: CGSize) -> CIImage {
        let rect = CGRect(origin: .zero, size: size)

        // Try to resolve bookmark to URL
        var isStale = false
        var url: URL?
        if let resolved = try? URL(resolvingBookmarkData: bookmarkData, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale) {
            _ = resolved.startAccessingSecurityScopedResource()
            url = resolved
        } else if let resolved = try? URL(resolvingBookmarkData: bookmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale) {
            url = resolved
        }

        guard let url, let nsImage = NSImage(contentsOf: url) else {
            return CIImage(color: CIColor.black).cropped(to: rect)
        }

        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return CIImage(color: CIColor.black).cropped(to: rect)
        }

        let ciImage = CIImage(cgImage: cgImage)
        let imgSize = ciImage.extent.size

        // Aspect-fill scale
        let scaleX = size.width / imgSize.width
        let scaleY = size.height / imgSize.height
        let scale = max(scaleX, scaleY)

        let lanczos = CIFilter.lanczosScaleTransform()
        lanczos.inputImage = ciImage
        lanczos.scale = Float(scale)
        lanczos.aspectRatio = 1.0
        guard let scaled = lanczos.outputImage else {
            return CIImage(color: CIColor.black).cropped(to: rect)
        }

        // Center crop
        let scaledSize = CGSize(width: imgSize.width * scale, height: imgSize.height * scale)
        let cropX = (scaledSize.width - size.width) / 2
        let cropY = (scaledSize.height - size.height) / 2
        return scaled.cropped(to: CGRect(x: cropX, y: cropY, width: size.width, height: size.height))
            .transformed(by: CGAffineTransform(translationX: -cropX, y: -cropY))
    }

    // MARK: - Frame Overlay

    nonisolated static func createFrameOverlay(
        style: FrameStyle,
        rect: CGRect,
        chromeHeight: CGFloat,
        cornerRadius: CGFloat,
        outputSize: CGSize,
        pointScale: CGFloat = 1.0
    ) -> CIImage? {
        switch style {
        case .none:
            return nil

        case .border(let width, let color):
            return createBorderOverlay(rect: rect, width: width * pointScale, color: color, cornerRadius: cornerRadius, outputSize: outputSize)

        case .gradientBorder(let width, let color1, let color2):
            return createGradientBorderOverlay(rect: rect, width: width * pointScale, color1: color1, color2: color2, cornerRadius: cornerRadius, outputSize: outputSize)

        case .neonGlow(let color, let radius):
            return createNeonGlowOverlay(rect: rect, color: color, radius: radius * pointScale, cornerRadius: cornerRadius, outputSize: outputSize)

        case .browserChrome:
            return createChromeOverlay(rect: rect, chromeHeight: chromeHeight, cornerRadius: cornerRadius, outputSize: outputSize, isBrowser: true, pointScale: pointScale)

        case .macOSWindow:
            return createChromeOverlay(rect: rect, chromeHeight: chromeHeight, cornerRadius: cornerRadius, outputSize: outputSize, isBrowser: false, pointScale: pointScale)
        }
    }

    private nonisolated static func createBorderOverlay(
        rect: CGRect, width: CGFloat, color: CodableColor,
        cornerRadius: CGFloat, outputSize: CGSize
    ) -> CIImage? {
        let w = Int(outputSize.width)
        let h = Int(outputSize.height)
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.clear(CGRect(origin: .zero, size: outputSize))

        let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        ctx.setStrokeColor(CGColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha))
        ctx.setLineWidth(width)
        ctx.addPath(path)
        ctx.strokePath()

        guard let cgImage = ctx.makeImage() else { return nil }
        return CIImage(cgImage: cgImage)
    }

    private nonisolated static func createGradientBorderOverlay(
        rect: CGRect, width: CGFloat, color1: CodableColor, color2: CodableColor,
        cornerRadius: CGFloat, outputSize: CGSize
    ) -> CIImage? {
        let w = Int(outputSize.width)
        let h = Int(outputSize.height)
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.clear(CGRect(origin: .zero, size: outputSize))

        // Clip to ring shape (outer - inner rounded rects)
        let outer = CGPath(roundedRect: rect.insetBy(dx: -width / 2, dy: -width / 2),
                           cornerWidth: cornerRadius + width / 2, cornerHeight: cornerRadius + width / 2, transform: nil)
        let inner = CGPath(roundedRect: rect.insetBy(dx: width / 2, dy: width / 2),
                           cornerWidth: max(0, cornerRadius - width / 2), cornerHeight: max(0, cornerRadius - width / 2), transform: nil)
        ctx.addPath(outer)
        ctx.addPath(inner)
        ctx.clip(using: .evenOdd)

        // Fill with gradient
        let colors = [
            CGColor(red: color1.red, green: color1.green, blue: color1.blue, alpha: color1.alpha),
            CGColor(red: color2.red, green: color2.green, blue: color2.blue, alpha: color2.alpha)
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: nil) {
            ctx.drawLinearGradient(gradient,
                start: CGPoint(x: rect.minX, y: rect.maxY),
                end: CGPoint(x: rect.maxX, y: rect.minY),
                options: [])
        }

        guard let cgImage = ctx.makeImage() else { return nil }
        return CIImage(cgImage: cgImage)
    }

    private nonisolated static func createNeonGlowOverlay(
        rect: CGRect, color: CodableColor, radius: CGFloat,
        cornerRadius: CGFloat, outputSize: CGSize
    ) -> CIImage? {
        let w = Int(outputSize.width)
        let h = Int(outputSize.height)
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.clear(CGRect(origin: .zero, size: outputSize))

        // Draw colored rounded rect outline — scale stroke for output resolution
        let glowScale = outputSize.height / 1080.0
        let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        ctx.setStrokeColor(CGColor(red: color.red, green: color.green, blue: color.blue, alpha: 0.9))
        ctx.setLineWidth(3.0 * glowScale)
        ctx.addPath(path)
        ctx.strokePath()

        guard let cgImage = ctx.makeImage() else { return nil }
        let ciImage = CIImage(cgImage: cgImage)

        // Apply Gaussian blur for glow
        let blurred = ciImage.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
        // Composite sharp over blurred for glow effect
        return ciImage.composited(over: blurred).cropped(to: CGRect(origin: .zero, size: outputSize))
    }

    private nonisolated static func createChromeOverlay(
        rect: CGRect, chromeHeight: CGFloat, cornerRadius: CGFloat,
        outputSize: CGSize, isBrowser: Bool, pointScale: CGFloat = 1.0
    ) -> CIImage? {
        let w = Int(outputSize.width)
        let h = Int(outputSize.height)
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.clear(CGRect(origin: .zero, size: outputSize))

        // Chrome bar sits above the video rect. In CIImage (bottom-left origin),
        // the chrome is at the top of the recording area.
        let chromeRect = CGRect(
            x: rect.minX,
            y: rect.maxY,
            width: rect.width,
            height: chromeHeight
        )

        // Draw chrome bar — top corners rounded, bottom corners sharp (meets video)
        ctx.setFillColor(CGColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1.0))
        let cr = cornerRadius
        let chromePath = CGMutablePath()
        // Start at bottom-left (sharp corner)
        chromePath.move(to: CGPoint(x: chromeRect.minX, y: chromeRect.minY))
        // Left edge up to top-left rounded corner
        chromePath.addLine(to: CGPoint(x: chromeRect.minX, y: chromeRect.maxY - cr))
        // Top-left rounded corner
        chromePath.addArc(tangent1End: CGPoint(x: chromeRect.minX, y: chromeRect.maxY),
                          tangent2End: CGPoint(x: chromeRect.minX + cr, y: chromeRect.maxY),
                          radius: cr)
        // Top edge to top-right rounded corner
        chromePath.addLine(to: CGPoint(x: chromeRect.maxX - cr, y: chromeRect.maxY))
        // Top-right rounded corner
        chromePath.addArc(tangent1End: CGPoint(x: chromeRect.maxX, y: chromeRect.maxY),
                          tangent2End: CGPoint(x: chromeRect.maxX, y: chromeRect.maxY - cr),
                          radius: cr)
        // Right edge down to bottom-right (sharp corner)
        chromePath.addLine(to: CGPoint(x: chromeRect.maxX, y: chromeRect.minY))
        chromePath.closeSubpath()
        ctx.addPath(chromePath)
        ctx.fillPath()

        // Separator line at bottom of chrome
        let sepInset = 8 * pointScale
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.06))
        ctx.setLineWidth(max(0.5, 0.5 * pointScale))
        ctx.move(to: CGPoint(x: chromeRect.minX + sepInset, y: chromeRect.minY))
        ctx.addLine(to: CGPoint(x: chromeRect.maxX - sepInset, y: chromeRect.minY))
        ctx.strokePath()

        // Traffic lights — scaled to output resolution
        let dotRadius = 6 * pointScale
        let dotStartX = chromeRect.minX + 16 * pointScale
        let dotSpacing = 22 * pointScale
        let dotY = chromeRect.midY
        let colors: [(r: CGFloat, g: CGFloat, b: CGFloat)] = [
            (1.0, 0.35, 0.33),   // red (close)
            (1.0, 0.78, 0.22),   // yellow (minimize)
            (0.25, 0.80, 0.35),  // green (maximize)
        ]
        for (i, c) in colors.enumerated() {
            let cx = dotStartX + CGFloat(i) * dotSpacing
            ctx.setFillColor(CGColor(red: c.r, green: c.g, blue: c.b, alpha: 1.0))
            ctx.fillEllipse(in: CGRect(x: cx - dotRadius, y: dotY - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
        }

        // Browser: address bar capsule
        if isBrowser {
            let barLeftPad = 12 * pointScale
            let barRightPad = 16 * pointScale
            let barX = dotStartX + 3 * dotSpacing + barLeftPad
            let barWidth = chromeRect.maxX - barX - barRightPad
            let barHeight = 24 * pointScale
            let barY = chromeRect.midY - barHeight / 2
            if barWidth > 40 * pointScale {
                let barRect = CGRect(x: barX, y: barY, width: barWidth, height: barHeight)
                let barPath = CGPath(roundedRect: barRect, cornerWidth: barHeight / 2, cornerHeight: barHeight / 2, transform: nil)
                ctx.setFillColor(CGColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1.0))
                ctx.addPath(barPath)
                ctx.fillPath()
            }
        }

        guard let cgImage = ctx.makeImage() else { return nil }
        return CIImage(cgImage: cgImage)
    }

    // MARK: - Masks

    private nonisolated static func createRoundedRectMask(
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

    /// Creates a mask that includes both the chrome bar and the video rect.
    private nonisolated static func createChromeMask(
        outputSize: CGSize,
        recordingRect: CGRect,
        chromeHeight: CGFloat,
        cornerRadius: CGFloat
    ) -> CIImage {
        let w = Int(outputSize.width)
        let h = Int(outputSize.height)

        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return CIImage(color: .white).cropped(to: CGRect(origin: .zero, size: outputSize))
        }

        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(origin: .zero, size: outputSize))

        // Union rect: chrome bar + video area
        let unionRect = CGRect(
            x: recordingRect.minX,
            y: recordingRect.minY,
            width: recordingRect.width,
            height: recordingRect.height + chromeHeight
        )

        ctx.setFillColor(gray: 1, alpha: 1)
        let path = CGPath(roundedRect: unionRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        ctx.addPath(path)
        ctx.fillPath()

        guard let cgImage = ctx.makeImage() else {
            return CIImage(color: .white).cropped(to: CGRect(origin: .zero, size: outputSize))
        }

        return CIImage(cgImage: cgImage)
    }

    // MARK: - Shadow

    private nonisolated static func createShadow(
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
}
