import Foundation

struct Feed {
    enum Format { case rss, substack }

    let kind: Kind
    let name: String
    let url: String
    var format: Format = .rss
    var limit = 6
    var shuffle = false
}

enum Feeds {
    static let all: [Feed] = [
        // News
        Feed(kind: .news, name: "NPR", url: "https://feeds.npr.org/1001/rss.xml", limit: 10),
        Feed(kind: .news, name: "The Guardian", url: "https://www.theguardian.com/world/rss", limit: 8),
        Feed(kind: .news, name: "PBS NewsHour", url: "https://www.pbs.org/newshour/feeds/rss/headlines", limit: 8),
        Feed(kind: .news, name: "Axios", url: "https://api.axios.com/feed/", limit: 8),

        // AI
        Feed(kind: .ai, name: "Ars Technica", url: "https://arstechnica.com/ai/feed/"),
        Feed(kind: .ai, name: "TechCrunch", url: "https://techcrunch.com/category/artificial-intelligence/feed/"),
        Feed(kind: .ai, name: "Simon Willison", url: "https://simonwillison.net/atom/entries/"),
        Feed(kind: .ai, name: "One Useful Thing", url: "https://www.oneusefulthing.org", format: .substack, limit: 4),
        Feed(kind: .ai, name: "Import AI", url: "https://importai.substack.com", format: .substack, limit: 4),
        Feed(kind: .ai, name: "Latent Space", url: "https://www.latent.space", format: .substack, limit: 4),
        Feed(kind: .ai, name: "Ben's Bites", url: "https://www.bensbites.com", format: .substack, limit: 4),

        // Research
        Feed(kind: .research, name: "Quanta Magazine", url: "https://api.quantamagazine.org/feed/", limit: 5),
        Feed(kind: .research, name: "Knowable Magazine", url: "https://knowablemagazine.org/rss", limit: 6),
        Feed(kind: .research, name: "The Conversation", url: "https://theconversation.com/us/technology/articles.atom", limit: 6),
        Feed(kind: .research, name: "ScienceDaily", url: "https://www.sciencedaily.com/rss/top/science.xml", limit: 6),

        // Reads
        Feed(kind: .reads, name: "Paul Graham", url: "http://www.aaronsw.com/2002/feeds/pgessays.rss", limit: 10, shuffle: true),
        Feed(kind: .reads, name: "Not Boring", url: "https://www.notboring.co", format: .substack, limit: 4),
        Feed(kind: .reads, name: "The Generalist", url: "https://thegeneralist.substack.com", format: .substack, limit: 4),
        Feed(kind: .reads, name: "Lenny's Newsletter", url: "https://www.lennysnewsletter.com", format: .substack, limit: 4),
        Feed(kind: .reads, name: "Farnam Street", url: "https://fs.blog/feed/", limit: 5),
        Feed(kind: .reads, name: "Kottke", url: "https://kottke.org/index.xml", limit: 6),
    ]

    static func substackArchiveURL(_ base: String) -> String { base + "/api/v1/archive?sort=new&limit=20" }

    static func freeSubstackPosts(_ data: Data) -> [(title: String, link: String)] {
        guard let posts = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return posts.compactMap { post in
            guard post["audience"] as? String == "everyone", let title = post["title"] as? String,
                  let link = post["canonical_url"] as? String else { return nil }
            return (title.trimmingCharacters(in: .whitespaces), link)
        }
    }
}

enum OnThisDayFilter {
    private static let interesting = try! NSRegularExpression(pattern:
        "\\b(art|artist|paint|photo|camera|film|movie|cinema|album|song|music|computer|software|internet|web|email|"
        + "video game|company|founded|launch|invent|patent|publish|book|novel|magazine|newspaper|first|museum|"
        + "premiere|release|broadcast|television|radio|space|nasa|spacecraft|probe|orbit|moon|discover|olympic|"
        + "champion|world record|all-time|apple|google|microsoft|ibm|iphone|disney|stock exchange)",
        options: [.caseInsensitive])
    private static let grim = try! NSRegularExpression(pattern:
        "\\b(war|battle|kill|massacre|attack|bomb|execut|murder|siege|army|troops|invad|assassin|earthquake|crash|"
        + "disaster|genocide|shot|terror|dies|died|death|typhoon|hurricane|coup|forces|riot|kidnap|protest)",
        options: [.caseInsensitive])

    static func line(year: Int?, text: String) -> String? {
        guard let year, year >= 1800 else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard interesting.firstMatch(in: text, range: range) != nil,
              grim.firstMatch(in: text, range: range) == nil else { return nil }
        let short = shorten(text)
        return short.count <= 100 ? "\(year): \(short)" : nil
    }

    static func shorten(_ text: String) -> String {
        var s = text.replacingOccurrences(of: "\\s*\\([^)]*\\)", with: "", options: .regularExpression)
        let cut = ";|, (which|who|but|after|becoming|making|marking|ending|leading|resulting|although|while|where)\\b| \u{2013} | \u{2014} "
        if let r = s.range(of: cut, options: .regularExpression) { s = String(s[..<r.lowerBound]) }
        s = s.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",")))
        return s.hasSuffix(".") ? s : s + "."
    }
}
