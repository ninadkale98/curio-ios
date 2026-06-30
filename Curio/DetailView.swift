import SwiftUI

// MARK: - DetailView
// Simple, typography-first long-form reader. No hero image, no chrome, no AI.
// Opened from a feed card by swipe-left; swipe-right to dismiss.
struct DetailView: View {
    let story: Story
    let onClose: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.safeTop) private var safeTop
    @Environment(\.safeBottom) private var safeBottom
    @State private var dragX: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                theme.pageBg.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        DetailArticleView(blocks: story.blocks)
                            .padding(.top, 30)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, safeTop + 28)
                    .padding(.bottom, safeBottom + 64)
                    .frame(width: geo.size.width, alignment: .leading)
                }
            }
            .background(theme.pageBg)
            .offset(x: max(dragX, 0))
            .simultaneousGesture(dismissSwipe)
        }
    }

    // MARK: Header — eyebrow, title, byline, rule
    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(story.category)
                .font(CurioFont.mono(11, weight: .semibold))
                .tracking(2.2)
                .foregroundColor(theme.accent)

            Text(story.title)
                .font(CurioFont.display(32, weight: .heavy))
                .foregroundColor(theme.text)
                .tracking(-0.5)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            HStack(spacing: 8) {
                Text(story.source)
                    .font(CurioFont.body(14, weight: .semibold))
                    .foregroundColor(theme.text)
                Circle().fill(theme.faint).frame(width: 3, height: 3)
                Text(story.readTime + " read")
                    .font(CurioFont.body(14))
                    .foregroundColor(theme.faint)
            }
            .padding(.top, 18)

            Rectangle()
                .fill(theme.line)
                .frame(height: 1)
                .padding(.top, 22)
        }
    }

    // Swipe-right dismisses (mirrors the swipe-left that opened it).
    private var dismissSwipe: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .local)
            .onChanged { v in
                guard abs(v.translation.width) > abs(v.translation.height), v.translation.width > 0 else { return }
                dragX = v.translation.width
            }
            .onEnded { v in
                if abs(v.translation.width) > abs(v.translation.height), v.translation.width > 90 {
                    onClose()
                }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { dragX = 0 }
            }
    }
}

// MARK: - DetailArticleView (clean long-form rendering)
struct DetailArticleView: View {
    let blocks: [ArticleBlock]
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
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
                .font(CurioFont.body(20, weight: .medium))
                .foregroundColor(theme.text)
                .lineSpacing(7)
                .fixedSize(horizontal: false, vertical: true)

        case .heading(let text):
            Text(text)
                .font(CurioFont.display(22, weight: .bold))
                .foregroundColor(theme.text)
                .tracking(-0.3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

        case .paragraph(let text):
            Text(MarkdownCache.attributed(text))
                .font(CurioFont.body(17.5))
                .foregroundColor(theme.text.opacity(0.86))
                .lineSpacing(9)
                .tint(theme.text)
                .fixedSize(horizontal: false, vertical: true)

        case .quote(let text, let cite):
            PullQuote(text: text, cite: cite)

        case .image(let url, let caption):
            DetailImage(url: url, caption: caption)

        case .table(let head, let rows):
            DetailTable(head: head, rows: rows)

        case .diagram(let title, let steps):
            DetailDiagram(title: title, steps: steps)
        }
    }
}

// MARK: Pull quote — thin accent rule, restrained
private struct PullQuote: View {
    let text: String
    let cite: String?
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            RoundedRectangle(cornerRadius: 2)
                .fill(theme.accent)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 12) {
                Text(text)
                    .font(CurioFont.display(21, weight: .semibold))
                    .foregroundColor(theme.text)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                if let cite {
                    Text(cite.uppercased())
                        .font(CurioFont.mono(10.5, weight: .medium))
                        .tracking(0.8)
                        .foregroundColor(theme.accent)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: Image
private struct DetailImage: View {
    let url: String
    let caption: String?
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CachedAsyncImage(url: url, hue: 0.58)
                .frame(height: 230)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.line, lineWidth: 1))
            if let caption {
                Text(caption)
                    .font(CurioFont.body(13))
                    .italic()
                    .foregroundColor(theme.faint)
            }
        }
    }
}

// MARK: Table
private struct DetailTable: View {
    let head: [String]
    let rows: [[String]]
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(Array(head.enumerated()), id: \.offset) { i, col in
                        Text(col)
                            .font(CurioFont.body(13, weight: .bold))
                            .foregroundColor(theme.text)
                            .frame(maxWidth: .infinity, alignment: i == 0 ? .leading : .trailing)
                            .padding(.horizontal, 13).padding(.vertical, 12)
                    }
                }
                .background(theme.elevated)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Rectangle().fill(theme.line).frame(height: 1)
                    HStack(spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { ci, cell in
                            Text(cell)
                                .font(CurioFont.body(13.5, weight: ci == 0 ? .medium : .regular))
                                .foregroundColor(ci == 0 ? theme.text : theme.sub)
                                .frame(maxWidth: .infinity, alignment: ci == 0 ? .leading : .trailing)
                                .padding(.horizontal, 13).padding(.vertical, 11)
                        }
                    }
                }
            }
            .frame(minWidth: CGFloat(head.count) * 104)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.line, lineWidth: 1))
    }
}

// MARK: Diagram
private struct DetailDiagram: View {
    let title: String?
    let steps: [String]
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let title {
                Text(title)
                    .font(CurioFont.mono(11, weight: .semibold))
                    .foregroundColor(theme.accent)
                    .tracking(1.4)
            }
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .top, spacing: 16) {
                    ZStack {
                        Circle().fill(theme.accent.opacity(0.16)).frame(width: 30, height: 30)
                        Text("\(i + 1)")
                            .font(CurioFont.body(14, weight: .bold))
                            .foregroundColor(theme.accent)
                    }
                    Text(MarkdownCache.attributed(step))
                        .font(CurioFont.body(15.5))
                        .foregroundColor(theme.text)
                        .lineSpacing(5)
                        .tint(theme.text)
                        .padding(.top, 4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(theme.line, lineWidth: 1))
    }
}

#Preview {
    DetailView(story: sampleStories[2], onClose: {})
        .environment(\.theme, .dark)
        .preferredColorScheme(.dark)
}
