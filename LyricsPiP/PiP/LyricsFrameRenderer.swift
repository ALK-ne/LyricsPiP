import UIKit
import CoreVideo
import CoreMedia

/// Renders the current + next lyric line into a pixel buffer suitable for
/// enqueueing onto an `AVSampleBufferDisplayLayer` for custom-content PIP.
enum LyricsFrameRenderer {
    /// One line to draw, plus whether it's the current (highlighted) line.
    struct Line: Equatable {
        let text: String
        let isCurrent: Bool
    }

    // Fixed width; the height grows with the number of lines (see frameSize).
    static let width: CGFloat = 720

    // Layout metrics. The current line gets a taller slot (bold, big font);
    // other lines a shorter one. Chosen so a 2-line frame (current + 1 next)
    // stays exactly 720x200 (3.6:1) — the ratio verified good on device —
    // while extra lines simply extend the height:
    //   topPad(8) + current(104) + (other(74)+gap(4))*(n-1) + bottomPad(10)
    private static let topPadding: CGFloat = 8
    private static let bottomPadding: CGFloat = 10
    private static let lineGap: CGFloat = 4
    private static let currentSlotHeight: CGFloat = 104
    private static let otherSlotHeight: CGFloat = 74

    /// Pixel size for a frame showing `lineCount` lines. The PiP window follows
    /// this aspect ratio, so more lines makes the floating window taller.
    static func frameSize(lineCount: Int) -> CGSize {
        let count = max(1, lineCount)
        let others = CGFloat(count - 1)
        let height = topPadding + currentSlotHeight + others * (otherSlotHeight + lineGap) + bottomPadding
        return CGSize(width: width, height: height)
    }

    /// Renders `lines` stacked top-to-bottom into `frameSize`. The current line
    /// is highlighted (bold/white/large); the rest are dimmed and smaller.
    static func renderImage(lines: [Line], frameSize: CGSize) -> CGImage? {
        let renderer = UIGraphicsImageRenderer(size: frameSize)
        let image = renderer.image { _ in
            UIColor.black.setFill()
            UIRectFill(CGRect(origin: .zero, size: frameSize))

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center

            let w = frameSize.width - 40
            var y = topPadding
            for line in lines {
                let slot = line.isCurrent ? currentSlotHeight : otherSlotHeight
                let rect = CGRect(x: 20, y: y, width: w, height: slot)
                if line.isCurrent {
                    drawFittedLine(
                        line.text.isEmpty ? "♪" : line.text,
                        in: rect,
                        maxFontSize: 44,
                        minFontSize: 16,
                        weight: .bold,
                        color: .white,
                        paragraphStyle: paragraph
                    )
                } else {
                    drawFittedLine(
                        line.text,
                        in: rect,
                        maxFontSize: 30,
                        minFontSize: 14,
                        weight: .regular,
                        color: UIColor(white: 1, alpha: 0.55),
                        paragraphStyle: paragraph
                    )
                }
                y += slot + lineGap
            }
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
