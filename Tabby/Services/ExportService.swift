import Foundation
import PDFKit
import AppKit

final class ExportService {
    static let shared = ExportService()
    private init() {}

    enum ExportFormat: String, CaseIterable {
        case csv      = "CSV"
        case json     = "JSON"
        case pdf      = "PDF"
        case html     = "HTML (Netscape)"
        case markdown = "Markdown"

        var fileExtension: String {
            switch self {
            case .csv:      return "csv"
            case .json:     return "json"
            case .pdf:      return "pdf"
            case .html:     return "html"
            case .markdown: return "md"
            }
        }
    }

    func export(bookmarks: [Bookmark], tags: [Tag], format: ExportFormat, to url: URL) throws {
        switch format {
        case .csv:      try exportCSV(bookmarks: bookmarks, to: url)
        case .json:     try exportJSON(bookmarks: bookmarks, tags: tags, to: url)
        case .pdf:      try exportPDF(bookmarks: bookmarks, tags: tags, to: url)
        case .html:     try exportHTML(bookmarks: bookmarks, to: url)
        case .markdown: try exportMarkdown(bookmarks: bookmarks, to: url)
        }
    }

    // MARK: - CSV

    private func exportCSV(bookmarks: [Bookmark], to url: URL) throws {
        var lines = ["Title,URL,Tags,Notes,Date Added,Click Count"]
        let df = ISO8601DateFormatter()
        for b in bookmarks {
            let cols: [String] = [
                csvEscape(b.displayTitle),
                csvEscape(b.url),
                csvEscape(b.tags.joined(separator: ";")),
                csvEscape(b.notes),
                csvEscape(df.string(from: b.dateAdded)),
                "\(b.clickCount)"
            ]
            lines.append(cols.joined(separator: ","))
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - JSON

    private func exportJSON(bookmarks: [Bookmark], tags: [Tag], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let payload = ExportPayload(bookmarks: bookmarks, tags: tags, exportDate: Date(), version: 1)
        let data = try encoder.encode(payload)
        try data.write(to: url, options: .atomicWrite)
    }

    // MARK: - HTML (Netscape Bookmark Format)

    private func exportHTML(bookmarks: [Bookmark], to url: URL) throws {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none

        let grouped = groupByTag(bookmarks: bookmarks)
        var html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <!-- This is an automatically generated file.
             It will be read and overwritten.
             DO NOT EDIT! -->
        <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
        <TITLE>Bookmarks</TITLE>
        <H1>Bookmarks</H1>
        <DL><p>
        """

        for (tag, items) in grouped.sorted(by: { $0.key < $1.key }) {
            html += "    <DT><H3>\(htmlEscape(tag))</H3>\n    <DL><p>\n"
            for b in items {
                let addDate = Int(b.dateAdded.timeIntervalSince1970)
                html += "        <DT><A HREF=\"\(htmlEscape(b.url))\" ADD_DATE=\"\(addDate)\">\(htmlEscape(b.displayTitle))</A>\n"
            }
            html += "    </DL><p>\n"
        }
        html += "</DL><p>\n"

        try html.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Markdown

    private func exportMarkdown(bookmarks: [Bookmark], to url: URL) throws {
        let grouped = groupByTag(bookmarks: bookmarks)
        var lines = ["# Tabby Bookmarks", "", "> Exported \(Date().shortDisplay)", ""]

        for (tag, items) in grouped.sorted(by: { $0.key < $1.key }) {
            lines.append("## \(tag)")
            lines.append("")
            for b in items {
                var line = "- [\(b.displayTitle)](\(b.url))"
                if !b.notes.isEmpty { line += " — \(b.notes)" }
                lines.append(line)
            }
            lines.append("")
        }

        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - PDF

    private func exportPDF(bookmarks: [Bookmark], tags: [Tag], to url: URL) throws {
        let pdfDocument = PDFDocument()
        let grouped = groupByTag(bookmarks: bookmarks).sorted(by: { $0.key < $1.key })

        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842) // A4
        let margin: CGFloat = 50

        let titleAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .bold),
            .foregroundColor: NSColor.labelColor
        ]
        let sectionAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let linkAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.systemBlue
        ]
        let noteAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        // Build full attributed string, then split into pages via PDFKit
        let fullText = NSMutableAttributedString()
        fullText.append(NSAttributedString(string: "Tabby Bookmarks\n\n", attributes: titleAttr))
        fullText.append(NSAttributedString(string: "Exported \(Date().shortDisplay)\n\n", attributes: noteAttr))

        for (tag, items) in grouped {
            fullText.append(NSAttributedString(string: "\(tag)\n", attributes: sectionAttr))
            for b in items {
                let linkStr = NSMutableAttributedString(string: "• \(b.displayTitle)\n", attributes: linkAttr)
                if let linkURL = URL(string: b.url) {
                    linkStr.addAttribute(.link, value: linkURL, range: NSRange(location: 2, length: b.displayTitle.count))
                }
                fullText.append(linkStr)
                if !b.notes.isEmpty {
                    fullText.append(NSAttributedString(string: "  \(b.notes)\n", attributes: noteAttr))
                }
            }
            fullText.append(NSAttributedString(string: "\n", attributes: noteAttr))
        }

        // Render single-page-style via NSTextContainer
        let textStorage = NSTextStorage(attributedString: fullText)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let containerSize = CGSize(width: pageRect.width - margin * 2, height: CGFloat.greatestFiniteMagnitude)
        let textContainer = NSTextContainer(size: containerSize)
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        layoutManager.ensureLayout(for: textContainer)

        let usedRect = layoutManager.usedRect(for: textContainer)
        let totalPages = max(1, Int(ceil(usedRect.height / (pageRect.height - margin * 2))))

        for pageIndex in 0..<totalPages {
            let pageTop = CGFloat(pageIndex) * (pageRect.height - margin * 2)
            let srcRect = CGRect(x: 0, y: pageTop, width: containerSize.width, height: pageRect.height - margin * 2)

            let pdfData = NSMutableData()
            let pdfConsumer = CGDataConsumer(data: pdfData)!
            var mediaBox = pageRect
            let ctx = CGContext(consumer: pdfConsumer, mediaBox: &mediaBox, nil)!

            ctx.beginPDFPage(nil)
            ctx.translateBy(x: margin, y: pageRect.height - margin)
            ctx.scaleBy(x: 1, y: -1)
            ctx.translateBy(x: 0, y: -srcRect.height)

            let glyphRange = layoutManager.glyphRange(forBoundingRect: srcRect, in: textContainer)
            layoutManager.drawBackground(forGlyphRange: glyphRange, at: CGPoint(x: 0, y: -pageTop))
            layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: CGPoint(x: 0, y: -pageTop))
            ctx.endPDFPage()
            ctx.closePDF()

            if let doc = PDFDocument(data: pdfData as Data), let page = doc.page(at: 0) {
                pdfDocument.insert(page, at: pdfDocument.pageCount)
            }
        }

        pdfDocument.write(to: url)
    }

    // MARK: - Helpers

    private func groupByTag(bookmarks: [Bookmark]) -> [String: [Bookmark]] {
        var result: [String: [Bookmark]] = ["Uncategorized": []]
        for b in bookmarks {
            if b.tags.isEmpty {
                result["Uncategorized", default: []].append(b)
            } else {
                for tag in b.tags {
                    result[tag, default: []].append(b)
                }
            }
        }
        if result["Uncategorized"]?.isEmpty == true {
            result.removeValue(forKey: "Uncategorized")
        }
        return result
    }

    private func csvEscape(_ string: String) -> String {
        let needsQuoting = string.contains(",") || string.contains("\"") || string.contains("\n")
        if needsQuoting {
            return "\"" + string.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return string
    }

    private func htmlEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

struct ExportPayload: Codable {
    let bookmarks: [Bookmark]
    let tags: [Tag]
    let exportDate: Date
    let version: Int
}

