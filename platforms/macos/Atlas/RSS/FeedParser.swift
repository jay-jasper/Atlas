import Foundation

struct FeedItem: Equatable, Identifiable {
    var id: String { link.isEmpty ? title : link }
    let title: String
    let link: String
    let summary: String
}

struct ParsedFeed: Equatable {
    let title: String
    let items: [FeedItem]
}

/// Parses RSS 2.0 and Atom feeds via `XMLParser`. Handles `<item>` (RSS) and
/// `<entry>` (Atom); for Atom, `<link href="…">` is read from attributes.
final class FeedParser: NSObject, XMLParserDelegate {
    private var feedTitle = ""
    private var items: [FeedItem] = []

    private var currentElement = ""
    private var inItem = false
    private var itemTitle = ""
    private var itemLink = ""
    private var itemSummary = ""
    private var sawChannelTitle = false
    private var text = ""

    static func parse(_ data: Data) -> ParsedFeed? {
        let parser = FeedParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        guard xml.parse() else { return nil }
        return ParsedFeed(title: parser.feedTitle, items: parser.items)
    }

    static func parse(_ string: String) -> ParsedFeed? {
        guard let data = string.data(using: .utf8) else { return nil }
        return parse(data)
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        currentElement = elementName
        text = ""
        if elementName == "item" || elementName == "entry" {
            inItem = true
            itemTitle = ""; itemLink = ""; itemSummary = ""
        }
        // Atom link is an attribute.
        if inItem, elementName == "link", let href = attributeDict["href"], !href.isEmpty {
            itemLink = href
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let string = String(data: CDATABlock, encoding: .utf8) { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if inItem {
            switch elementName {
            case "title": itemTitle = trimmed
            case "link": if itemLink.isEmpty { itemLink = trimmed }
            case "description", "summary", "content": if itemSummary.isEmpty { itemSummary = trimmed }
            case "item", "entry":
                items.append(FeedItem(title: itemTitle, link: itemLink, summary: itemSummary))
                inItem = false
            default: break
            }
        } else if elementName == "title", !sawChannelTitle {
            feedTitle = trimmed
            sawChannelTitle = true
        }
        text = ""
    }
}
