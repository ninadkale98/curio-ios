import Foundation

// MARK: - Article Blocks
// Codable with a "type" discriminator so a backend can return article bodies
// as JSON arrays:  [{ "type": "paragraph", "text": "..." }, ...]
enum ArticleBlock: Identifiable, Codable, Hashable {
    case lead(String)
    case heading(String)
    case paragraph(String)
    case quote(text: String, cite: String?)
    case image(url: String, caption: String?)
    case table(head: [String], rows: [[String]])
    case diagram(title: String?, steps: [String])

    // Stable identity for ForEach / diffing in lazy lists.
    var id: Int { hashValue }

    private enum CodingKeys: String, CodingKey {
        case type, text, cite, url, caption, head, rows, title, steps
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "lead":      self = .lead(try c.decode(String.self, forKey: .text))
        case "heading":   self = .heading(try c.decode(String.self, forKey: .text))
        case "paragraph": self = .paragraph(try c.decode(String.self, forKey: .text))
        case "quote":
            self = .quote(text: try c.decode(String.self, forKey: .text),
                          cite: try c.decodeIfPresent(String.self, forKey: .cite))
        case "image":
            self = .image(url: try c.decode(String.self, forKey: .url),
                          caption: try c.decodeIfPresent(String.self, forKey: .caption))
        case "table":
            self = .table(head: try c.decode([String].self, forKey: .head),
                          rows: try c.decode([[String]].self, forKey: .rows))
        case "diagram":
            self = .diagram(title: try c.decodeIfPresent(String.self, forKey: .title),
                            steps: try c.decode([String].self, forKey: .steps))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c,
                debugDescription: "Unknown ArticleBlock type: \(type)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .lead(let t):      try c.encode("lead", forKey: .type);      try c.encode(t, forKey: .text)
        case .heading(let t):   try c.encode("heading", forKey: .type);   try c.encode(t, forKey: .text)
        case .paragraph(let t): try c.encode("paragraph", forKey: .type); try c.encode(t, forKey: .text)
        case .quote(let t, let cite):
            try c.encode("quote", forKey: .type); try c.encode(t, forKey: .text)
            try c.encodeIfPresent(cite, forKey: .cite)
        case .image(let url, let caption):
            try c.encode("image", forKey: .type); try c.encode(url, forKey: .url)
            try c.encodeIfPresent(caption, forKey: .caption)
        case .table(let head, let rows):
            try c.encode("table", forKey: .type); try c.encode(head, forKey: .head); try c.encode(rows, forKey: .rows)
        case .diagram(let title, let steps):
            try c.encode("diagram", forKey: .type)
            try c.encodeIfPresent(title, forKey: .title); try c.encode(steps, forKey: .steps)
        }
    }
}

// MARK: - Prompt
struct Prompt: Identifiable, Codable, Hashable {
    var id: String { question }
    let question: String
    let answer: String
}

// MARK: - Chat
enum ChatRole: String, Codable { case user, ai }

struct ChatMessage: Identifiable, Hashable {
    let id = UUID()
    let role: ChatRole
    var text: String
}

// MARK: - Story
struct Story: Identifiable, Codable, Hashable {
    let id: String
    let source: String
    let mono: String           // 2-letter badge
    let category: String
    let readTime: String
    let author: String         // byline name
    let date: String           // display date, e.g. "Jun 24, 2025"
    let title: String
    let summary: String
    let imageURL: String
    let likes: Int
    let hue: Double            // 0–1, for gradient fallback
    let chatIntro: String      // one-line AI framing shown as opening bubble
    let blocks: [ArticleBlock] // REEL card payload: collapsed preview + double-tap inline expand
    let prompts: [Prompt]
    // READER payload: full premium article as house-styled semantic HTML.
    // Independent of `blocks`. If nil, the reader derives HTML from `blocks`.
    var bodyHTML: String? = nil

    static func == (lhs: Story, rhs: Story) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
