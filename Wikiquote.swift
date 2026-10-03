import Foundation

enum Wikiquote {
    static let authors: [(page: String, name: String)] = [
        ("Seneca_the_Younger", "Seneca"), ("Epictetus", "Epictetus"), ("Marcus_Aurelius", "Marcus Aurelius"),
        ("Andrew_Grove", "Andy Grove"), ("Peter_Thiel", "Peter Thiel"), ("Paul_Graham", "Paul Graham"),
        ("Ben_Horowitz", "Ben Horowitz"), ("Jeff_Bezos", "Jeff Bezos"), ("Marc_Andreessen", "Marc Andreessen"),
        ("Peter_Drucker", "Peter Drucker"), ("Charlie_Munger", "Charlie Munger"), ("Warren_Buffett", "Warren Buffett"),
        ("David_Ogilvy", "David Ogilvy"), ("Nassim_Nicholas_Taleb", "Nassim Nicholas Taleb"), ("Ray_Dalio", "Ray Dalio"),
        ("Mark_Zuckerberg", "Mark Zuckerberg"),
        ("Mike_Tyson", "Mike Tyson"), ("Bruce_Lee", "Bruce Lee"), ("Muhammad_Ali", "Muhammad Ali"),
        ("Kobe_Bryant", "Kobe Bryant"), ("Michael_Jordan", "Michael Jordan"), ("Vince_Lombardi", "Vince Lombardi"),
        ("Sun_Tzu", "Sun Tzu"),
        ("Elmore_Leonard", "Elmore Leonard"), ("Kurt_Vonnegut", "Kurt Vonnegut"), ("Anne_Lamott", "Anne Lamott"),
        ("Jack_London", "Jack London"), ("William_Zinsser", "William Zinsser"), ("Ernest_Hemingway", "Ernest Hemingway"),
        ("Hunter_S._Thompson", "Hunter S. Thompson"),
        ("Henri_Cartier-Bresson", "Henri Cartier-Bresson"), ("Robert_Capa", "Robert Capa"), ("Ansel_Adams", "Ansel Adams"),
        ("Dorothea_Lange", "Dorothea Lange"), ("Diane_Arbus", "Diane Arbus"), ("Garry_Winogrand", "Garry Winogrand"),
        ("Andy_Warhol", "Andy Warhol"), ("Dieter_Rams", "Dieter Rams"), ("Stanley_Kubrick", "Stanley Kubrick"),
        ("Werner_Herzog", "Werner Herzog"),
    ]

    static func apiURL(for page: String) -> String {
        "https://en.wikiquote.org/w/api.php?action=parse&page=\(page)&prop=wikitext&format=json&formatversion=2&redirects=1"
    }

    static func pageURL(for page: String) -> URL? { URL(string: "https://en.wikiquote.org/wiki/\(page)") }

    private static let stopSections = try! NSRegularExpression(
        pattern: "^==\\s*(disputed|misattributed|attributed|unsourced|quotes about|about |external links|see also|sources|references)",
        options: [.caseInsensitive])
    private static let skipSections = try! NSRegularExpression(
        pattern: "women|religion|politic|trump|sex|race|drugs|quotes about|dialogue", options: [.caseInsensitive])
    private static let citationHints = ["http", "cited", "quoted", "p. ", "pp.", "Letter ", "Interview", "(19", "(20",
                                        "{{", "In:", "ch.", "Chapter", "line ", "Ibid", "Source", "Often ", "Sometimes ",
                                        "Variant", "Alternate", "translat", "Book ", "Vol.", "episode", "Original:"]

    static func quotes(fromWikitext wikitext: String) -> [(text: String, highlight: Bool)] {
        var results: [(text: String, highlight: Bool)] = []
        var skipping = false
        let lines = wikitext.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let range = NSRange(line.startIndex..., in: line)
            if line.hasPrefix("==") {
                if line.hasPrefix("=="), !line.hasPrefix("==="), stopSections.firstMatch(in: line, range: range) != nil { break }
                skipping = skipSections.firstMatch(in: line, range: range) != nil
                continue
            }
            guard !skipping, line.hasPrefix("*"), !line.hasPrefix("**") else { continue }

            var raw = String(line.dropFirst())
            // original-language line, use the translation under it
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            let isOriginal = (trimmed.hasPrefix("''") && !trimmed.hasPrefix("'''")) || !isLatinScript(clean(trimmed))
            if isOriginal, index + 1 < lines.count, lines[index + 1].hasPrefix("**"), !lines[index + 1].hasPrefix("***") {
                let next = String(lines[index + 1].dropFirst(2))
                if citationHints.contains(where: next.contains) { continue }
                raw = next
            }
            if let quote = pick(from: raw) { results.append(quote) }
        }
        return results
    }

    private static func pick(from raw: String) -> (text: String, highlight: Bool)? {
        let bold = try! NSRegularExpression(pattern: "'''(.+?)'''")
        let range = NSRange(raw.startIndex..., in: raw)
        for match in bold.matches(in: raw, range: range) {
            guard let r = Range(match.range(at: 1), in: raw) else { continue }
            guard let candidate = finish(clean(String(raw[r]))) else { continue }
            if isUsable(candidate), candidate.first?.isUppercase == true { return (candidate, true) }
        }
        guard let whole = finish(clean(raw)) else { return nil }
        return isUsable(whole) && whole.count <= 120 ? (whole, false) : nil
    }

    static func isUsable(_ text: String) -> Bool {
        (20...150).contains(text.count) && text.contains(" ")
            && text.last.map { ".!?\"”’".contains($0) } == true
            && !text.contains(where: { "[]{}|=<>".contains($0) })
            && !text.lowercased().hasPrefix("as quoted")
            && isLatinScript(text)
            && !text.contains(".\" ") && !text.contains("\" (")
            && !blocked.contains(where: text.lowercased().contains)
    }

    // rot13 so they aren't spelled out in the source
    private static let blocked = [
        "shpx", "fuvg", "ovgpu", "qnza", "onyyf", "pbpx", "qvpx", "juber", "encr", "cvff", "onfgneq", "uryy",
        "cbyvgvp", "jnesner", "avtt", "snt", "ergneq", "xvyy", "zheqre", "fhvpvqr", "qnuzre", "uvgyre", "anmv",
        "pbpnvar", "urebva", "qeht", "juvgr", "oynpx", "jbzra", "wrj", "fynir"
    ].map(rot13)

    private static func rot13(_ text: String) -> String {
        String(text.unicodeScalars.map { c -> Character in
            switch c {
            case "a"..."z": return Character(UnicodeScalar((c.value - 97 + 13) % 26 + 97)!)
            case "A"..."Z": return Character(UnicodeScalar((c.value - 65 + 13) % 26 + 65)!)
            default: return Character(c)
            }
        })
    }

    static func isLatinScript(_ text: String) -> Bool {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return false }
        let latin = letters.filter { $0.value < 0x0250 }
        return Double(latin.count) / Double(letters.count) > 0.95
    }

    static func clean(_ text: String) -> String {
        var s = text
        let replacements: [(String, String)] = [
            ("<ref[^>]*/>", ""), ("<ref[^>]*>.*?</ref>", ""),
            ("\\{\\{[^{}]*\\}\\}", ""), ("\\{\\{[^{}]*\\}\\}", ""),
            ("\\[\\[(?:[^\\]|]*\\|)?([^\\]]*)\\]\\]", "$1"),
            ("\\[https?://\\S+\\s([^\\]]*)\\]", "$1"), ("\\[https?://[^\\]]*\\]", ""),
            ("<[^>]+>", ""), ("'''?", ""),
            ("&nbsp;", " "), ("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"),
            ("\\s+", " "),
        ]
        for (pattern, template) in replacements {
            s = s.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return unwrap(s.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"“”"))))
    }

    static func words(_ text: String) -> Set<String> {
        Set(text.lowercased().split { !$0.isLetter && !$0.isNumber && $0 != "'" }.map(String.init).filter { $0.count >= 4 })
    }

    static func isNearDuplicate(_ a: Set<String>, _ b: Set<String>) -> Bool {
        guard !a.isEmpty, !b.isEmpty else { return false }
        return Double(a.intersection(b).count) / Double(a.union(b).count) >= 0.4
    }

    static func dedupe<T>(_ items: [T], against existing: [String] = [], text: (T) -> String) -> [T] {
        var seen = existing.map(words)
        var kept: [T] = []
        for item in items {
            let w = words(text(item))
            if seen.contains(where: { isNearDuplicate($0, w) }) { continue }
            seen.append(w)
            kept.append(item)
        }
        return kept
    }

    private static let danglers: Set<String> = ["that", "the", "a", "an", "of", "to", "and", "or", "but", "in", "on",
                                                "for", "with", "as", "which", "who", "is", "are", "was", "be", "by", "from",
                                                "if", "up", "my", "our", "their", "this"]

    // drop trailing notes, reject mid-sentence fragments, add a missing period
    static func finish(_ text: String) -> String? {
        let s = unwrap(text).replacingOccurrences(of: "\\s*\\([^()]*\\)$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if let last = s.last, ".!?\"\u{201D}\u{2019}".contains(last) { return s }
        let lastWord = s.split(separator: " ").last.map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }
        if let lastWord, danglers.contains(lastWord) { return nil }
        return s.trimmingCharacters(in: CharacterSet(charactersIn: ",;: -\u{2013}\u{2014}")) + "."
    }

    static func unwrap(_ text: String) -> String {
        guard text.hasPrefix("("), text.hasSuffix(")"),
              text.dropFirst().dropLast().allSatisfy({ $0 != "(" && $0 != ")" }) else { return text }
        return String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
    }
}
