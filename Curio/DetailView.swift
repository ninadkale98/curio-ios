import SwiftUI

// MARK: - Reading progress preference
private struct ReaderScrollKey: PreferenceKey {
    static var defaultValue: CGFloat = 0            // 0…1 reading progress
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - DetailView
// Premium, reading-first long-form reader. Hero image up top (the swipe-left
// morph lands on it), then title, byline, rule, body. The horizontal open/close
// transition is driven by FeedView — this view only REPORTS its right-drag so
// the dismissal tracks the finger 1:1 and a quick flick bails instantly.
struct DetailView: View {
    let story: Story
    let onCloseDragChanged: (CGFloat) -> Void        // live right-drag translation
    let onCloseDragEnded: (CGFloat, CGFloat) -> Void // final translation, predicted end
    let onClose: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.safeTop) private var safeTop
    @Environment(\.safeBottom) private var safeBottom
    @State private var readProgress: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                theme.pageBg.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        hero(geo)
                        articleColumn(geo)
                    }
                    .background(
                        GeometryReader { g in
                            let minY = g.frame(in: .named("readerScroll")).minY
                            let scrollable = max(g.size.height - geo.size.height, 1)
                            Color.clear.preference(key: ReaderScrollKey.self,
                                                   value: min(1, max(0, -minY / scrollable)))
                        }
                    )
                }
                .coordinateSpace(name: "readerScroll")
                .ignoresSafeArea(edges: .top)
                .onPreferenceChange(ReaderScrollKey.self) { readProgress = $0 }

                // Thin reading-progress bar pinned to the very top.
                Rectangle()
                    .fill(theme.accent)
                    .frame(width: max(0, geo.size.width * readProgress), height: 2.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .allowsHitTesting(false)

                // Always-available way back (in addition to swipe-right).
                backButton
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 16)
                    .padding(.top, safeTop + 4)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .background(theme.pageBg)
            .contentShape(Rectangle())
            .simultaneousGesture(closeDrag)
        }
    }

    // MARK: Hero
    private func hero(_ geo: GeometryProxy) -> some View {
        let h = geo.size.height * 0.4
        return CachedAsyncImage(url: story.imageURL, hue: story.hue)
            .frame(width: geo.size.width, height: h)
            .clipped()
            // Fade the image bottom into the page so text begins seamlessly.
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [theme.pageBg.opacity(0), theme.pageBg],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: h * 0.55)
            }
            // Legibility scrim behind the back button.
            .overlay(alignment: .top) {
                LinearGradient(colors: [.black.opacity(0.4), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: safeTop + 56)
                    .allowsHitTesting(false)
            }
    }

    // MARK: Article column
    private func articleColumn(_ geo: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(story.category)
                .font(CurioFont.mono(11, weight: .semibold))
                .tracking(2.2)
                .foregroundColor(theme.accent)

            Text(story.title)
                .font(CurioFont.display(30, weight: .heavy))
                .foregroundColor(theme.text)
                .tracking(-0.5)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            byline
                .padding(.top, 18)

            Rectangle()
                .fill(theme.line)
                .frame(height: 1)
                .padding(.top, 20)

            DetailArticleView(blocks: story.blocks)
                .padding(.top, 26)
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, safeBottom + 80)
        .frame(width: geo.size.width, alignment: .leading)
    }

    // MARK: Byline — avatar chip + author, then source · date · read time
    private var byline: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(theme.elevated)
                    .frame(width: 36, height: 36)
                Text(story.mono)
                    .font(CurioFont.body(12.5, weight: .bold))
                    .foregroundColor(theme.text)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(story.author)
                    .font(CurioFont.body(14.5, weight: .semibold))
                    .foregroundColor(theme.text)
                HStack(spacing: 7) {
                    Text(story.source)
                    dot
                    Text(story.date)
                    dot
                    Text(story.readTime + " read")
                }
                .font(CurioFont.body(12.5))
                .foregroundColor(theme.faint)
            }
        }
    }

    private var dot: some View { Circle().fill(theme.faint).frame(width: 3, height: 3) }

    // MARK: Back button
    private var backButton: some View {
        Button(action: onClose) {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.16), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // Right-drag dismisses — reported to FeedView so it tracks the finger.
    private var closeDrag: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { v in
                guard abs(v.translation.width) > abs(v.translation.height),
                      v.translation.width > 0 else { return }
                onCloseDragChanged(v.translation.width)
            }
            .onEnded { v in
                guard abs(v.translation.width) > abs(v.translation.height),
                      v.translation.width > 0 else { onCloseDragEnded(0, 0); return }
                onCloseDragEnded(v.translation.width, v.predictedEndTranslation.width)
            }
    }
}

// MARK: - DetailArticleView (clean long-form rendering)
struct DetailArticleView: View {
    let blocks: [ArticleBlock]
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
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
                .foregroundColor(theme.text.opacity(0.92))
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
    DetailView(story: sampleStories[2],
               onCloseDragChanged: { _ in },
               onCloseDragEnded: { _, _ in },
               onClose: {})
        .environment(\.theme, .dark)
        .preferredColorScheme(.dark)
}
