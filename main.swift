import AppKit

// MARK: - Model

enum Kind: String, CaseIterable {
    case quote, fact, news, ai, research, reads, history, mine

    var label: String {
        switch self {
        case .quote: return "Quotes"
        case .fact: return "Interesting facts"
        case .news: return "News headlines"
        case .ai: return "AI news & tips"
        case .research: return "Research"
        case .reads: return "Good reads"
        case .history: return "On this day"
        case .mine: return "My own lines"
        }
    }

    var singular: String {
        switch self {
        case .quote: return "Quote"
        case .fact: return "Fact"
        case .news: return "News"
        case .ai: return "AI"
        case .research: return "Research"
        case .reads: return "Read"
        case .history: return "On this day"
        case .mine: return "Mine"
        }
    }

    var symbol: String {
        switch self {
        case .quote: return "quote.opening"
        case .fact: return "lightbulb"
        case .news: return "newspaper"
        case .ai: return "sparkles"
        case .research: return "graduationcap"
        case .reads: return "book"
        case .history: return "calendar"
        case .mine: return "heart"
        }
    }
}

struct Item: Equatable {
    let kind: Kind
    let text: String
    let source: String?
    var url: URL? = nil
}

struct StoredQuote: Codable, Equatable {
    let text: String
    let source: String
    let page: String

    var item: Item { Item(kind: .quote, text: text, source: source, url: Wikiquote.pageURL(for: page)) }
}

// MARK: - Online sources

final class FeedParser: NSObject, XMLParserDelegate {
    private(set) var entries: [(title: String, link: String)] = []
    private var inEntry = false
    private var buffer = ""
    private var title = ""
    private var link = ""

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        if name == "item" || name == "entry" { inEntry = true; title = ""; link = "" }
        if inEntry, name == "link", link.isEmpty, let href = attributes["href"] { link = href }
        buffer = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { buffer += string }

    func parser(_ parser: XMLParser, foundCDATA data: Data) {
        buffer += String(data: data, encoding: .utf8) ?? ""
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard inEntry else { return }
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "title": title = text
        case "link": if link.isEmpty { link = text }
        case "item", "entry":
            if !title.isEmpty { entries.append((title, link)) }
            inEntry = false
        default: break
        }
    }
}

struct OnThisDay: Decodable {
    struct Event: Decodable {
        struct Page: Decodable {
            struct URLs: Decodable { struct Desktop: Decodable { let page: String? }; let desktop: Desktop? }
            let content_urls: URLs?
        }
        let text: String
        let year: Int?
        let pages: [Page]?
    }
    let selected: [Event]?
    let events: [Event]?
}

// MARK: - App

@MainActor
final class Ticker: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let userAgent = "Ticker/1.0 (personal macOS menu bar app)"

    let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let menu = NSMenu()
    let defaults = UserDefaults.standard

    var pools: [Kind: [Item]] = [:]
    var bags: [Kind: [Item]] = [:]
    var current: Item?
    var history: [Item] = []
    var rotateTimer: Timer?
    var refreshTimer: Timer?
    var historyDay = ""
    let marquee = MarqueeView(frame: .zero)
    var fetchedQuotes: [StoredQuote] = []
    lazy var ratings = RatingStore(directory: supportDir)
    var isFetchingQuotes = false

    var intervalSeconds: Int {
        get { defaults.object(forKey: "intervalSeconds") as? Int ?? 15 }
        set { defaults.set(newValue, forKey: "intervalSeconds") }
    }
    var barWidth: Int {
        get { defaults.object(forKey: "barWidth") as? Int ?? 0 }
        set { defaults.set(newValue, forKey: "barWidth") }
    }
    var hidden: Set<String> {
        get { Set(defaults.stringArray(forKey: "hidden") ?? []) }
        set { defaults.set(Array(newValue), forKey: "hidden") }
    }
    func isEnabled(_ kind: Kind) -> Bool { defaults.object(forKey: "show.\(kind.rawValue)") as? Bool ?? true }

    var supportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ticker", isDirectory: true)
    }
    var mineFile: URL { supportDir.appendingPathComponent("my-lines.txt") }
    var fetchedFile: URL { supportDir.appendingPathComponent("fetched-quotes.json") }
    var launchAgent: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/local.ticker.plist")
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        if let data = try? Data(contentsOf: fetchedFile),
           let stored = try? JSONDecoder().decode([StoredQuote].self, from: data) {
            let pages = Set(Wikiquote.authors.map(\.page))
            let cleaned = stored.compactMap { quote in
                Wikiquote.finish(quote.text).map { StoredQuote(text: $0, source: quote.source, page: quote.page) }
            }.filter { pages.contains($0.page) && Wikiquote.isUsable($0.text) }
            fetchedQuotes = Wikiquote.dedupe(cleaned, against: Content.quotes.map(\.0)) { $0.text }
        }
        rebuildQuotePool()
        pools[.fact] = Content.facts.map { Item(kind: .fact, text: $0, source: nil) }
        ensureMineFile()
        loadMine()

        menu.delegate = self
        if let button = status.button {
            button.addSubview(marquee)
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }

        if defaults.object(forKey: "didFirstRun") == nil {
            defaults.set(true, forKey: "didFirstRun")
            setOpenAtLogin(true)
        }

        advance()
        scheduleRotation()
        refreshOnline()
        refreshTimer = Timer.scheduledTimer(timeInterval: 30 * 60, target: self,
                                            selector: #selector(refreshOnline), userInfo: nil, repeats: true)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake),
                                                          name: NSWorkspace.didWakeNotification, object: nil)
    }

    // MARK: Rotation

    func scheduleRotation() {
        rotateTimer?.invalidate()
        // let a scrolling line finish one pass before moving on
        let delay = max(TimeInterval(intervalSeconds), marquee.loopDuration + 2)
        rotateTimer = Timer.scheduledTimer(timeInterval: delay, target: self,
                                           selector: #selector(rotate), userInfo: nil, repeats: false)
        rotateTimer?.tolerance = min(5, delay / 10)
    }

    @objc func rotate() {
        advance()
        scheduleRotation()
    }

    @objc func advance() {
        loadMine()
        let kinds = Kind.allCases.filter { isEnabled($0) && !(pools[$0] ?? []).isEmpty }
        guard !kinds.isEmpty else {
            show(Item(kind: .quote, text: "Nothing to show. Turn a category back on.", source: nil))
            return
        }
        let choices = kinds.count > 1 ? kinds.filter { $0 != current?.kind } : kinds
        let weights = choices.map { ratings.weight(for: $0) * min(1, Double(pools[$0]?.count ?? 0) / 6) }
        var roll = Double.random(in: 0..<weights.reduce(0, +))
        let kind = zip(choices, weights).first { roll -= $0.1; return roll < 0 }?.0 ?? choices[0]

        var next: Item?
        for _ in 0..<2 where next == nil {
            if (bags[kind] ?? []).isEmpty {
                var bag = pools[kind]!.filter(isAllowed).shuffled()
                if bag.count > 1, bag.last == current { bag.swapAt(0, bag.count - 1) }
                bags[kind] = bag
            }
            while let candidate = bags[kind]?.popLast() {
                if isAllowed(candidate) { next = candidate; break }
            }
        }
        guard let next else { return }
        if let current { history.append(current); history = Array(history.suffix(30)) }
        show(next)
    }

    func isAllowed(_ item: Item) -> Bool {
        !hidden.contains(item.text) && !(item.kind == .quote && ratings.score(author: item.source) <= -2)
    }

    @objc func goBack() {
        guard let previous = history.popLast() else { return }
        show(previous)
        scheduleRotation()
    }

    @objc func nextNow() {
        advance()
        scheduleRotation()
    }

    var maxTextWidth: CGFloat {
        guard barWidth == 0 else { return CGFloat(barWidth) }
        let screenWidth = (status.button?.window?.screen ?? NSScreen.main)?.frame.width ?? 1440
        return min(1300, screenWidth * 0.45)
    }

    func show(_ item: Item) {
        current = item
        guard let button = status.button else { return }
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        let image = NSImage(systemSymbolName: item.kind.symbol, accessibilityDescription: item.kind.label)?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        status.length = marquee.set(text: item.text, image: image, rating: ratings.value(for: item),
                                    maxTextWidth: maxTextWidth,
                                    height: NSStatusBar.system.thickness)
        button.toolTip = [item.text, item.source].compactMap { $0 }.joined(separator: "\n")
        button.setAccessibilityLabel(item.text)
    }

    // MARK: Content loading

    func ensureMineFile() {
        guard !FileManager.default.fileExists(atPath: mineFile.path) else { return }
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        let starter = """
        # Add your own lines here, one per line. Save the file and they join the rotation.
        # Lines starting with # are ignored. To add a source, put it after a | like this:
        # Ship the work, then make it better. | Me

        """
        try? starter.write(to: mineFile, atomically: true, encoding: .utf8)
    }

    func loadMine() {
        let raw = (try? String(contentsOf: mineFile, encoding: .utf8)) ?? ""
        let items: [Item] = raw.split(whereSeparator: \.isNewline).compactMap { line in
            let line = line.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
            let parts = line.split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            return Item(kind: .mine, text: parts[0], source: parts.count > 1 ? parts[1] : nil)
        }
        if items != pools[.mine] ?? [] {
            pools[.mine] = items
            bags[.mine] = nil
        }
    }

    @objc func didWake() {
        refreshOnline()
        advance()
        scheduleRotation()
    }

    @objc func refreshOnline() {
        Task { await loadFeeds() }
        Task { await loadOnThisDay() }
        Task { await loadMoreQuotes() }
    }

    func rebuildQuotePool() {
        let builtIn = Content.quotes.map { Item(kind: .quote, text: $0.0, source: $0.1) }
        pools[.quote] = builtIn + fetchedQuotes.map(\.item)
    }

    func loadMoreQuotes() async {
        let last = defaults.object(forKey: "lastQuoteFetch") as? Date ?? .distantPast
        guard !isFetchingQuotes, Date().timeIntervalSince(last) > 4 * 3600 || fetchedQuotes.count < 100 else { return }
        isFetchingQuotes = true
        defer { isFetchingQuotes = false }

        var recent = defaults.stringArray(forKey: "recentAuthors") ?? []
        let known = Set(fetchedQuotes.map(\.text) + Content.quotes.map(\.0))
        var fresh: [StoredQuote] = []
        let eligible = Wikiquote.authors.filter {
            let score = ratings.score(author: $0.name)
            return score > -2 && (!recent.contains($0.page) || score >= 2)
        }
        var chosen: [(page: String, name: String)] = []
        var remaining = eligible
        while chosen.count < 6, !remaining.isEmpty {
            let weights = remaining.map { max(0.25, 1 + Double(ratings.score(author: $0.name))) }
            var roll = Double.random(in: 0..<weights.reduce(0, +))
            let index = weights.firstIndex { roll -= $0; return roll < 0 } ?? 0
            chosen.append(remaining.remove(at: index))
        }
        for author in chosen {
            guard let data = await fetch(Wikiquote.apiURL(for: author.page)),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let parse = json["parse"] as? [String: Any],
                  let wikitext = parse["wikitext"] as? String else { continue }
            let candidates = Wikiquote.quotes(fromWikitext: wikitext).filter { !known.contains($0.text) }
            let ranked = candidates.filter(\.highlight).shuffled() + candidates.filter { !$0.highlight }.shuffled()
            let picks = Wikiquote.dedupe(ranked, against: Array(known) + fresh.map(\.text)) { $0.text }
            fresh += picks.prefix(12).map { StoredQuote(text: $0.text, source: author.name, page: author.page) }
            recent.append(author.page)
        }
        defaults.set(Array(recent.suffix(Wikiquote.authors.count - 6)), forKey: "recentAuthors")
        guard !fresh.isEmpty else { return }

        defaults.set(Date(), forKey: "lastQuoteFetch")
        fetchedQuotes = Array((fetchedQuotes + fresh).suffix(3000))
        if let data = try? JSONEncoder().encode(fetchedQuotes) {
            try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
            try? data.write(to: fetchedFile)
        }
        rebuildQuotePool()
        bags[.quote] = ((bags[.quote] ?? []) + fresh.map(\.item)).shuffled()
    }

    func fetch(_ urlString: String) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return try? await URLSession.shared.data(for: request).0
    }

    func loadFeeds() async {
        var found: [Kind: [Item]] = [:]
        for feed in Feeds.all {
            let isSubstack = feed.format == .substack
            guard let data = await fetch(isSubstack ? Feeds.substackArchiveURL(feed.url) : feed.url) else { continue }
            var entries: [(title: String, link: String)]
            if isSubstack {
                entries = Feeds.freeSubstackPosts(data)
            } else {
                let parser = XMLParser(data: data)
                let delegate = FeedParser()
                parser.delegate = delegate
                parser.parse()
                entries = delegate.entries
            }
            if feed.shuffle { entries.shuffle() }
            found[feed.kind, default: []] += entries.prefix(feed.limit).map {
                Item(kind: feed.kind, text: $0.title, source: isSubstack ? "\(feed.name) (Substack)" : feed.name,
                     url: URL(string: $0.link))
            }
        }
        for (kind, items) in found where !items.isEmpty { merge(items, into: kind) }
    }

    func merge(_ items: [Item], into kind: Kind) {
        let old = Set((pools[kind] ?? []).map(\.text))
        let fresh = items.filter { !old.contains($0.text) }
        let keep = Set(items.map(\.text))
        pools[kind] = items
        bags[kind] = ((bags[kind] ?? []).filter { keep.contains($0.text) } + fresh).shuffled()
    }

    func loadOnThisDay() async {
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        let day = formatter.string(from: now)
        guard day != historyDay else { return }
        guard let data = await fetch("https://api.wikimedia.org/feed/v1/wikipedia/en/onthisday/all/\(day)"),
              let decoded = try? JSONDecoder().decode(OnThisDay.self, from: data) else { return }
        var seen = Set<String>()
        let items: [Item] = ((decoded.selected ?? []) + (decoded.events ?? [])).compactMap { event in
            guard let line = OnThisDayFilter.line(year: event.year, text: event.text), seen.insert(line).inserted
            else { return nil }
            let link = event.pages?.first?.content_urls?.desktop?.page
            return Item(kind: .history, text: line, source: "Wikipedia", url: link.flatMap(URL.init(string:)))
        }
        guard !items.isEmpty else { return }
        historyDay = day
        pools[.history] = items
        bags[.history] = nil
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if let current {
            let card = NSMenuItem()
            card.view = cardView(for: current)
            menu.addItem(card)
            if let url = current.url {
                let label = current.kind == .history ? "Read on Wikipedia"
                    : current.kind == .quote ? "See source on Wikiquote" : "Open article"
                let open = add(to: menu, label, #selector(openLink))
                open.representedObject = url
            }
            add(to: menu, "Copy", #selector(copyCurrent))
            add(to: menu, ratings.value(for: current) == 1 ? "Liked" : "Like", #selector(likeCurrent)).state =
                ratings.value(for: current) == 1 ? .on : .off
            add(to: menu, "Dislike and skip", #selector(dislikeCurrent))
            menu.addItem(.separator())
        }

        add(to: menu, "Next", #selector(nextNow), key: "n")
        add(to: menu, "Previous", #selector(goBack), key: "b").isEnabled = !history.isEmpty
        menu.addItem(.separator())

        let show = NSMenu()
        for kind in Kind.allCases {
            let item = add(to: show, kind.label, #selector(toggleKind))
            item.representedObject = kind.rawValue
            item.state = isEnabled(kind) ? .on : .off
        }
        submenu(menu, "Show", show)

        let every = NSMenu()
        for (label, seconds) in [("15 seconds", 15), ("30 seconds", 30), ("1 minute", 60), ("5 minutes", 300),
                                 ("15 minutes", 900), ("1 hour", 3600)] {
            let item = add(to: every, label, #selector(setInterval))
            item.representedObject = seconds
            item.state = seconds == intervalSeconds ? .on : .off
        }
        submenu(menu, "Change every", every)

        let length = NSMenu()
        for (label, points) in [("Short", 240), ("Medium", 340), ("Long", 440), ("Extra long", 600), ("Full", 0)] {
            let item = add(to: length, label, #selector(setLength))
            item.representedObject = points
            item.state = points == barWidth ? .on : .off
        }
        submenu(menu, "Menu bar width", length)

        add(to: menu, "Add my own lines…", #selector(openMine))
        add(to: menu, "See my ratings…", #selector(openRatings))
        menu.addItem(.separator())
        add(to: menu, "Open at login", #selector(toggleLogin)).state = isOpenAtLogin ? .on : .off
        add(to: menu, "Quit Ticker", #selector(quit), key: "q")
    }

    @discardableResult
    func add(to menu: NSMenu, _ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    func submenu(_ menu: NSMenu, _ title: String, _ sub: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = sub
        menu.addItem(item)
    }

    func cardView(for item: Item) -> NSView {
        let width: CGFloat = 420, padX: CGFloat = 14, padY: CGFloat = 8
        let text = NSTextField(wrappingLabelWithString: item.text)
        text.font = .systemFont(ofSize: 13, weight: .medium)
        text.preferredMaxLayoutWidth = width
        let meta = NSTextField(labelWithString: [item.kind.singular, item.source].compactMap { $0 }.joined(separator: " · "))
        meta.font = .systemFont(ofSize: 11)
        meta.textColor = .secondaryLabelColor

        let textHeight = text.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 1000)).height
        let metaHeight = meta.fittingSize.height
        let view = NSView(frame: NSRect(x: 0, y: 0, width: width + padX * 2,
                                        height: padY * 2 + textHeight + 4 + metaHeight))
        meta.frame = NSRect(x: padX, y: padY, width: width, height: metaHeight)
        text.frame = NSRect(x: padX, y: padY + metaHeight + 4, width: width, height: textHeight)
        view.addSubview(text)
        view.addSubview(meta)
        return view
    }

    // MARK: Actions

    @objc func openLink(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { NSWorkspace.shared.open(url) }
    }

    @objc func copyCurrent() {
        guard let current else { return }
        let text = [current.text, current.source.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc func toggleKind(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let kind = Kind(rawValue: raw) else { return }
        defaults.set(!isEnabled(kind), forKey: "show.\(raw)")
        if kind == .mine, isEnabled(kind), (pools[.mine] ?? []).isEmpty { openMine() }
        if current?.kind == kind, !isEnabled(kind) { nextNow() }
    }

    @objc func setInterval(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? Int else { return }
        intervalSeconds = seconds
        scheduleRotation()
    }

    @objc func setLength(_ sender: NSMenuItem) {
        guard let points = sender.representedObject as? Int else { return }
        barWidth = points
        if let current { show(current) }
    }

    @objc func statusClicked() {
        guard let event = NSApp.currentEvent, let button = status.button else { return }
        if event.type == .leftMouseDown, let window = button.window {
            // currentEvent's location isn't reliable here
            let point = marquee.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
            switch marquee.zone(at: point) {
            case .like: likeCurrent(); return
            case .dislike: dislikeCurrent(); return
            case .body: break
            }
        }
        status.menu = menu
        button.performClick(nil)
        status.menu = nil
    }

    @objc func likeCurrent() {
        guard let current else { return }
        ratings.rate(current, 1)
        marquee.setRating(ratings.value(for: current))
    }

    @objc func dislikeCurrent() {
        guard let current else { return }
        if ratings.value(for: current) != -1 { ratings.rate(current, -1) }
        hidden.insert(current.text)
        bags[current.kind]?.removeAll { $0.text == current.text }
        nextNow()
    }

    @objc func openRatings() {
        if !FileManager.default.fileExists(atPath: ratings.summaryURL.path) {
            try? "# Ticker ratings\n\nNo ratings yet. Tap thumbs up or down in the menu bar.\n"
                .write(to: ratings.summaryURL, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open([ratings.summaryURL], withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                                configuration: NSWorkspace.OpenConfiguration())
    }

    @objc func openMine() {
        ensureMineFile()
        let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        NSWorkspace.shared.open([mineFile], withApplicationAt: textEdit,
                                configuration: NSWorkspace.OpenConfiguration())
    }

    var isOpenAtLogin: Bool { FileManager.default.fileExists(atPath: launchAgent.path) }

    func setOpenAtLogin(_ on: Bool) {
        if on {
            let plist: [String: Any] = [
                "Label": "local.ticker",
                "ProgramArguments": ["/usr/bin/open", "-a", Bundle.main.bundlePath],
                "RunAtLoad": true,
            ]
            try? FileManager.default.createDirectory(at: launchAgent.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
                try? data.write(to: launchAgent)
            }
        } else {
            try? FileManager.default.removeItem(at: launchAgent)
        }
    }

    @objc func toggleLogin() { setOpenAtLogin(!isOpenAtLogin) }

    @objc func quit() { NSApp.terminate(nil) }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let ticker = Ticker()
    app.delegate = ticker
    app.setActivationPolicy(.accessory)
    app.run()
}
