import UIKit
import CoreVideo
import CoreMedia

/// Renders the current + next lyric line into a pixel buffer suitable for
/// enqueueing onto an `AVSampleBufferDisplayLayer` for custom-content PIP.
enum LyricsFrameRenderer {
    static let frameSize = CGSize(width: 640, height: 360)

    static func renderImage(currentLine: String?, nextLine: String?) -> CGImage? {
        let renderer = UIGraphicsImageRenderer(size: frameSize)
        let image = renderer.image { _ in
            // TEMP DEBUG: bright green instead of black, to check whether
            // any rendered color at all is reaching the PIP window before
            // debugging text visibility specifically.
            UIColor(red: 0, green: 1, blue: 0, alpha: 1).setFill()
            UIRectFill(CGRect(origin: .zero, size: frameSize))

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center

            let currentAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 32),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ]
            let nextAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22),
                .foregroundColor: UIColor(white: 1, alpha: 0.55),
                .paragraphStyle: paragraph
            ]

            let currentText = currentLine ?? "♪"
            let nextText = nextLine ?? ""

            let currentRect = CGRect(x: 20, y: frameSize.height / 2 - 50, width: frameSize.width - 40, height: 60)
            let nextRect = CGRect(x: 20, y: frameSize.height / 2 + 20, width: frameSize.width - 40, height: 40)

            (currentText as NSString).draw(in: currentRect, withAttributes: currentAttrs)
            (nextText as NSString).draw(in: nextRect, withAttributes: nextAttrs)
        }
        return image.cgImage
    }

    static func makeSampleBuffer(from cgImage: CGImage, presentationTime: CMTime) -> CMSampleBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
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
