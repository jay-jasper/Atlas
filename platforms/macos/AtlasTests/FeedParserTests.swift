import XCTest
@testable import Atlas

@MainActor
final class FeedParserTests: XCTestCase {
    func testParsesRSS2() {
        let rss = """
        <?xml version="1.0"?>
        <rss version="2.0"><channel>
          <title>Example Blog</title>
          <item><title>First Post</title><link>https://example.com/1</link><description>Hello</description></item>
          <item><title>Second Post</title><link>https://example.com/2</link><description>World</description></item>
        </channel></rss>
        """
        let feed = FeedParser.parse(rss)
        XCTAssertEqual(feed?.title, "Example Blog")
        XCTAssertEqual(feed?.items.count, 2)
        XCTAssertEqual(feed?.items.first, FeedItem(title: "First Post", link: "https://example.com/1", summary: "Hello"))
    }

    func testParsesAtomWithLinkAttribute() {
        let atom = """
        <?xml version="1.0"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Atom Feed</title>
          <entry><title>Entry One</title><link href="https://example.com/a"/><summary>Summary A</summary></entry>
        </feed>
        """
        let feed = FeedParser.parse(atom)
        XCTAssertEqual(feed?.title, "Atom Feed")
        XCTAssertEqual(feed?.items.first?.link, "https://example.com/a")
        XCTAssertEqual(feed?.items.first?.summary, "Summary A")
    }

    func testHandlesCDATA() {
        let rss = """
        <rss><channel><title>T</title>
        <item><title><![CDATA[Bold Title]]></title><link>x</link><description><![CDATA[<b>hi</b>]]></description></item>
        </channel></rss>
        """
        let feed = FeedParser.parse(rss)
        XCTAssertEqual(feed?.items.first?.title, "Bold Title")
        XCTAssertEqual(feed?.items.first?.summary, "<b>hi</b>")
    }

    func testInvalidXMLReturnsNil() {
        XCTAssertNil(FeedParser.parse("not xml <<<"))
    }
}

private struct StubFetcher: FeedFetching {
    let data: Data?
    func fetch(_ url: URL) async -> Data? { data }
}

@MainActor
final class RSSServiceTests: XCTestCase {
    private let sampleRSS = """
    <rss><channel><title>Blog</title>
    <item><title>P1</title><link>https://x/1</link><description>d</description></item>
    </channel></rss>
    """

    func testAddFeedStoresSubscriptionWithTitle() async {
        let service = RSSService(store: InMemoryRSSStore(), fetcher: StubFetcher(data: Data(sampleRSS.utf8)))
        await service.addFeed(url: "https://x/feed.xml")
        XCTAssertEqual(service.subscriptions.count, 1)
        XCTAssertEqual(service.subscriptions.first?.title, "Blog")
    }

    func testRefreshAllCollectsItems() async {
        let store = InMemoryRSSStore(subscriptions: [FeedSubscription(url: "https://x/feed.xml", title: "Blog")])
        let service = RSSService(store: store, fetcher: StubFetcher(data: Data(sampleRSS.utf8)))
        await service.refreshAll()
        XCTAssertEqual(service.items.map(\.title), ["P1"])
    }

    func testDelete() async {
        let sub = FeedSubscription(url: "u", title: "t")
        let service = RSSService(store: InMemoryRSSStore(subscriptions: [sub]), fetcher: StubFetcher(data: nil))
        service.delete(id: sub.id)
        XCTAssertTrue(service.subscriptions.isEmpty)
    }
}
