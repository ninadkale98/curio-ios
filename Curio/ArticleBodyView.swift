import SwiftUI

// MARK: - Markdown cache (performance)
// Parsing markdown is non-trivial; memoize so fast scrolling never re-parses.
private final class AttrBox { let value: AttributedString; init(_ v: AttributedString) { value = v } }

enum MarkdownCache {
    private static let cache = NSCache<NSString, AttrBox>()

    static func attributed(_ string: String) -> AttributedString {
        let key = string as NSString
        if let hit = cache.object(forKey: key) { return hit.value }
        let parsed = (try? AttributedString(
            markdown: string,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(string)
        cache.setObject(AttrBox(parsed), forKey: key)
        return parsed
    }
}

// MARK: - Markdown text view
struct MarkdownText: View {
    let text: String
    let size: CGFloat
    let baseColor: Color
    var weight: Font.Weight = .regular
    var lineSpacing: CGFloat = 6

    var body: some View {
        Text(MarkdownCache.attributed(text))
            .font(CurioFont.body(size, weight: weight))
            .foregroundColor(baseColor)
            .lineSpacing(lineSpacing)
            .tint(baseColor)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - ArticleBodyView
struct ArticleBodyView: View {
    let blocks: [ArticleBlock]
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(blocks) { block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: ArticleBlock) -> some View {
        switch block {
        case .lead(let text):
            Text(text)
                .font(CurioFont.body(18, weight: .medium))
                .foregroundColor(theme.text)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)

        case .heading(let text):
            Text(text)
                .font(CurioFont.display(20, weight: .bold))
                .foregroundColor(theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

        case .paragraph(let text):
            MarkdownText(text: text, size: 16, baseColor: theme.sub)

        case .quote(let text, let cite):
            QuoteView(text: text, cite: cite)

        case .image(let url, let caption):
            ImageBlockView(url: url, caption: caption)

        case .table(let head, let rows):
            TableBlockView(head: head, rows: rows)

        case .diagram(let title, let steps):
            DiagramView(title: title, steps: steps)
        }
    }
}

// MARK: - Quote
private struct QuoteView: View {
    let text: String
    let cite: String?
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 2)
                .fill(theme.accent)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 8) {
                Text(text)
                    .font(CurioFont.display(20, weight: .semibold))
                    .foregroundColor(theme.text)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                if let cite {
                    Text(cite.uppercased())
                        .font(CurioFont.mono(11, weight: .medium))
                        .tracking(0.6)
                        .foregroundColor(theme.accent)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Image block
private struct ImageBlockView: View {
    let url: String
    let caption: String?
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CachedAsyncImage(url: url, hue: 0.58)
                .frame(height: 210)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(theme.line, lineWidth: 1)
                )

            if let caption {
                Text(caption)
                    .font(CurioFont.body(12.5))
                    .italic()
                    .foregroundColor(theme.faint)
                    .padding(.horizontal, 2)
            }
        }
    }
}

// MARK: - Table block
private struct TableBlockView: View {
    let head: [String]
    let rows: [[String]]
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(Array(head.enumerated()), id: \.offset) { i, col in
                        Text(col)
                            .font(CurioFont.body(12.5, weight: .bold))
                            .foregroundColor(theme.text)
                            .frame(maxWidth: .infinity, alignment: i == 0 ? .leading : .trailing)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 11)
                    }
                }
                .background(theme.elevated)

                ForEach(Array(rows.enumerated()), id: \.offset) { ri, row in
                    Rectangle().fill(theme.line).frame(height: 1)
                    HStack(spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { ci, cell in
                            Text(cell)
                                .font(CurioFont.body(13, weight: ci == 0 ? .medium : .regular))
                                .foregroundColor(ci == 0 ? theme.text : theme.sub)
                                .frame(maxWidth: .infinity, alignment: ci == 0 ? .leading : .trailing)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                        }
                    }
                }
            }
            .frame(minWidth: CGFloat(head.count) * 96)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(theme.line, lineWidth: 1)
        )
    }
}

// MARK: - Diagram
private struct DiagramView: View {
    let title: String?
    let steps: [String]
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let title {
                Text(title)
                    .font(CurioFont.mono(11, weight: .semibold))
                    .foregroundColor(theme.accent)
                    .tracking(1.4)
            }

            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(theme.accent.opacity(0.16))
                                .frame(width: 26, height: 26)
                            Text("\(i + 1)")
                                .font(CurioFont.body(13, weight: .bold))
                                .foregroundColor(theme.accent)
                        }
                        MarkdownText(text: step, size: 14.5, baseColor: theme.text, lineSpacing: 4)
                            .padding(.top, 2)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(theme.line, lineWidth: 1)
        )
    }
}

#Preview {
    ScrollView {
        ArticleBodyView(blocks: sampleStories[2].blocks)
            .padding()
    }
    .background(Palette.dark.surface)
    .environment(\.theme, .dark)
    .preferredColorScheme(.dark)
}
