import UIKit
import CoreVideo
import CoreMedia

/// Renders the current + next lyric line into a pixel buffer suitable for
/// enqueueing onto an `AVSampleBufferDisplayLayer` for custom-content PIP.
enum LyricsFrameRenderer {
    // 3:1 (wide/short) so the PiP window follows this ratio, minimizing the
    // vertical black margin around the two lyric lines. The PiP window shape is
    // determined by this frame's aspect ratio.
    static let frameSize = CGSize(width: 720, height: 240)

    static func renderImage(currentLine: String?, nextLine: String?) -> CGImage? {
        let renderer = UIGraphicsImageRenderer(size: frameSize)
        let image = renderer.image { _ in
            UIColor.black.setFill()
            UIRectFill(CGRect(origin: .zero, size: frameSize))

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center

            let w = frameSize.width - 48
            let currentRect = CGRect(x: 24, y: 34, width: w, height: 96)
            let nextRect = CGRect(x: 24, y: 140, width: w, height: 66)

            drawFittedLine(
                currentLine ?? "♪",
                in: currentRect,
                maxFontSize: 42,
                minFontSize: 16,
                weight: .bold,
                color: .white,
                paragraphStyle: paragraph
            )
            drawFittedLine(
                nextLine ?? "",
                in: nextRect,
                maxFontSize: 28,
                minFontSize: 14,
                weight: .regular,
                color: UIColor(white: 1, alpha: 0.55),
                paragraphStyle: paragraph
            )
        }
        return image.cgImage
    }

    /// Draws `text` shrunk to fit within `rect`'s width (down to `minFontSize`)
    /// and vertically centered in `rect`. Lyric lines vary a lot in length,
    /// and a fixed font size clipped the tail of longer lines off the edge
    /// of the small PIP surface instead of shrinking to fit.
    private static func drawFittedLine(
        _ text: String,
        in rect: CGRect,
        maxFontSize: CGFloat,
        minFontSize: CGFloat,
        weight: UIFont.Weight,
        color: UIColor,
        paragraphStyle: NSParagraphStyle
    ) {
        let nsText = text as NSString
        guard nsText.length > 0 else { return }

        var fontSize = maxFontSize
        var font = UIFont.systemFont(ofSize: fontSize, weight: weight)
        while fontSize > minFontSize {
            let width = nsText.size(withAttributes: [.font: font]).width
            if width <= rect.width { break }
            fontSize -= 1
            font = UIFont.systemFont(ofSize: fontSize, weight: weight)
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]
        let textHeight = nsText.size(withAttributes: attrs).height
        let yOffset = rect.origin.y + max(0, (rect.height - textHeight) / 2)
        let drawRect = CGRect(x: rect.origin.x, y: yOffset, width: rect.width, height: textHeight)
        nsText.draw(in: drawRect, withAttributes: attrs)
    }

    static func makeSampleBuffer(from cgImage: CGImage, presentationTime: CMTime) -> CMSampleBuffer? {
        var pixelBuffer: CVPixelBuffer?
        // kCVPixelBufferIOSurfacePropertiesKey is required (not optional) for
        // buffers that need to be composited by the system outside this
        // process, like a PIP window — without it, enqueue() succeeds and no
        // error is ever raised, but nothing actually renders on screen.
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ]
        let width = cgImage.width
        let height = cgImage.height

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: buffer,
            formatDescriptionOut: &formatDescription
        )
        guard let formatDescription else { return nil }

        var timingInfo = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: buffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )

        // Without this, AVSampleBufferDisplayLayer waits for its internal
        // clock/timebase to reach the sample's presentationTimeStamp before
        // showing it — but nothing is driving that clock for still-frame
        // (non-video) content, so the frame would sit enqueued forever and
        // the layer would just show black. This tells it to show the frame
        // the moment it's enqueued instead.
        if let sampleBuffer,
           let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
           CFArrayGetCount(attachmentsArray) > 0 {
            let attachments = unsafeBitCast(
                CFArrayGetValueAtIndex(attachmentsArray, 0),
                to: CFMutableDictionary.self
            )
            CFDictionarySetValue(
                attachments,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }

        return sampleBuffer
    }
}
