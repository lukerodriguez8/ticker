import Foundation

struct Rating: Codable {
    let date: Date
    let kind: String
    let text: String
    let source: String?
    let value: Int  // 1 or -1
}

@MainActor
final class RatingStore {
    private(set) var ratings: [Rating] = []
    let jsonURL: URL
    let summaryURL: URL

    init(directory: URL) {
        jsonURL = directory.appendingPathComponent("ratings.json")
        summaryURL = directory.appendingPathComponent("ratings.md")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: jsonURL), let saved = try? decoder.decode([Rating].self, from: data) {
            ratings = saved
        }
    }

    func value(for item: Item) -> Int? { ratings.last { $0.text == item.text }?.value }

    func rate(_ item: Item, _ value: Int) {
        let previous = self.value(for: item)
        ratings.removeAll { $0.text == item.text }
        if previous != value {
            ratings.append(Rating(date: Date(), kind: item.kind.rawValue, text: item.text, source: item.source, value: value))
        }
        save()
    }

    func score(kind: Kind) -> Int { ratings.filter { $0.kind == kind.rawValue }.reduce(0) { $0 + $1.value } }

    func score(author: String?) -> Int {
        guard let author else { return 0 }
        return ratings.filter { $0.kind == Kind.quote.rawValue && $0.source == author }.reduce(0) { $0 + $1.value }
    }

    func weight(for kind: Kind) -> Double { min(2.5, max(0.4, 1 + 0.15 * Double(score(kind: kind)))) }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        try? FileManager.default.createDirectory(at: jsonURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? encoder.encode(ratings) { try? data.write(to: jsonURL) }
        try? summary().write(to: summaryURL, atomically: true, encoding: .utf8)
    }

    private func summary() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        func line(_ r: Rating) -> String {
            let kind = Kind(rawValue: r.kind)?.singular ?? r.kind
            return "- \(formatter.string(from: r.date)) · \(kind) · \"\(r.text)\"" + (r.source.map { " (\($0))" } ?? "")
        }
        let likes = ratings.filter { $0.value > 0 }
        let dislikes = ratings.filter { $0.value < 0 }

        var out = "# Ticker ratings\n\nWritten by Ticker every time you tap thumbs up or down. "
        out += "Use it to see what you like and to retune the built-in quotes and facts.\n\n"
        out += "\(likes.count) liked, \(dislikes.count) disliked.\n\n## By category\n"
        for kind in Kind.allCases {
            let rated = ratings.filter { $0.kind == kind.rawValue }
            guard !rated.isEmpty else { continue }
            let up = rated.filter { $0.value > 0 }.count
            out += "- \(kind.label): \(up) up, \(rated.count - up) down\n"
        }
        let authors = Dictionary(grouping: ratings.filter { $0.kind == Kind.quote.rawValue && $0.source != nil }) { $0.source! }
        if !authors.isEmpty {
            out += "\n## Quote authors (net score)\n"
            for (name, rated) in authors.sorted(by: { $0.value.reduce(0) { $0 + $1.value } > $1.value.reduce(0) { $0 + $1.value } }) {
                let net = rated.reduce(0) { $0 + $1.value }
                out += "- \(name): \(net > 0 ? "+" : "")\(net)\n"
            }
        }
        out += "\n## Liked\n" + (likes.isEmpty ? "- None yet\n" : likes.reversed().map(line).joined(separator: "\n") + "\n")
        out += "\n## Disliked\n" + (dislikes.isEmpty ? "- None yet\n" : dislikes.reversed().map(line).joined(separator: "\n") + "\n")
        return out
    }
}
