import Cocoa

final class ClipboardMonitor {
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?
    private let onText: (String) -> Void
    private let onImage: (Data, String?) -> Void
    private let onPDF: (Data, String?) -> Void

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "gif", "tiff", "tif", "webp", "bmp"
    ]
    private static let maxFileLoadBytes: Int64 = 50 * 1024 * 1024
    private static let pdfPasteboardType = NSPasteboard.PasteboardType("com.adobe.pdf")
    private static let shortcodePattern = #":[a-z0-9+][a-z0-9_+\-]*:"#
    private static let maxRichTextBytes = 256 * 1024

    init(
        onText: @escaping (String) -> Void,
        onImage: @escaping (Data, String?) -> Void,
        onPDF: @escaping (Data, String?) -> Void
    ) {
        self.onText = onText
        self.onImage = onImage
        self.onPDF = onPDF
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]) ?? []
        let firstFileURL = urls.first(where: { $0.isFileURL })

        if let url = firstFileURL {
            let ext = url.pathExtension.lowercased()
            if Self.imageExtensions.contains(ext) {
                if let (png, name) = loadImageFile(at: url) {
                    onImage(png, name)
                    return
                }
            } else if ext == "pdf" {
                if let (data, name) = loadAnyFile(at: url) {
                    onPDF(data, name)
                    return
                }
            }
            // unsupported file kind — fall through to text (filename)
        } else {
            if let pdf = pasteboard.data(forType: Self.pdfPasteboardType) {
                onPDF(pdf, nil)
                return
            }
            if let png = readPNG() {
                onImage(png, nil)
                return
            }
        }

        if let text = bestPlainText() {
            onText(text)
        }
    }

    /// Returns the best plain-text representation of the pasteboard content.
    /// If the plain text looks like it contains emoji shortcodes (e.g. ":melting_face:"
    /// from Slack/Discord), we try to read the RTF/HTML version instead — those
    /// formats usually contain the actual unicode emoji glyph.
    private func bestPlainText() -> String? {
        let plain = pasteboard.string(forType: .string)
        if let p = plain, !p.isEmpty,
           p.range(of: Self.shortcodePattern, options: .regularExpression) != nil,
           let rich = richTextString(), !rich.isEmpty {
            return rich
        }
        if let p = plain, !p.isEmpty { return p }
        return nil
    }

    private func richTextString() -> String? {
        if let rtf = pasteboard.data(forType: .rtf), rtf.count < Self.maxRichTextBytes,
           let attr = try? NSAttributedString(
                data: rtf,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
           ) {
            return attr.string
        }
        if let html = pasteboard.data(forType: .html), html.count < Self.maxRichTextBytes,
           let attr = try? NSAttributedString(
                data: html,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ],
                documentAttributes: nil
           ) {
            return attr.string
        }
        return nil
    }

    private func readPNG() -> Data? {
        if let data = pasteboard.data(forType: .png) {
            return data
        }
        if let tiff = pasteboard.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiff) {
            return rep.representation(using: .png, properties: [:])
        }
        return nil
    }

    private func loadImageFile(at url: URL) -> (Data, String)? {
        let ext = url.pathExtension.lowercased()
        guard Self.imageExtensions.contains(ext) else { return nil }

        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? NSNumber,
           size.int64Value > Self.maxFileLoadBytes {
            return nil
        }

        guard let data = try? Data(contentsOf: url) else { return nil }
        let filename = url.lastPathComponent

        if ext == "png" {
            return (data, filename)
        }

        guard let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return nil
        }
        return (png, filename)
    }

    private func loadAnyFile(at url: URL) -> (Data, String)? {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? NSNumber,
           size.int64Value > Self.maxFileLoadBytes {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (data, url.lastPathComponent)
    }

    static func write(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    static func writeImage(_ pngData: Data) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(pngData, forType: .png)
        if let img = NSImage(data: pngData), let tiff = img.tiffRepresentation {
            pb.setData(tiff, forType: .tiff)
        }
    }

    static func writePDF(_ pdfData: Data) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(pdfData, forType: pdfPasteboardType)
    }
}
