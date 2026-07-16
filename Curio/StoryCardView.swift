import SwiftUI

// MARK: - StoryCardView
// A full-screen reel card. Double-tap expands/collapses the article inline.
// Swipe-left opens the detailed blog reader; swipe-right is reserved.
struct StoryCardView: View {
    let story: Story
    let isExpanded: Bool
    let isLiked: Bool
    let isSaved: Bool
    let likeCount: Int
    let onExpandToggle: () -> Void   // double-tap
    let onLike: () -> Void
    let onSave: () -> Void
    // Horizontal swipe-to-open is handled by the pager's UIKit pan recognizer
    // (VerticalPagerController), not here — a SwiftUI gesture on content inside
    // the scroll view fought the vertical scroll.

    @Environment(\.theme) private var theme
    @Environment(\.safeTop) private var safeTop
    @Environment(\.safeBottom) private var safeBottom
    @State private var likeBump: CGFloat = 1

    // Constant image height in both states — the cover no longer morphs/resizes
    // on expand, so the image never re-crops. The whole image is shown (fit).
    private var coverHeight: CGFloat { 0.40 }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                cover(geo: geo)
                content(geo: geo)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .background(theme.surface)
            .clipped()   // the collapsed preview overflows by design — keep it inside the card
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { toggleExpand() }
            // Pill + fade live on the card's full-screen coordinate space (reliable),
            // not inside the cover/content (which mis-position child overlays).
            .overlay(alignment: .topLeading) {
                categoryPill
                    .padding(.leading, 20)
                    .padding(.top, safeTop + 8)
                    .opacity(isExpanded ? 0 : 1)
                    .animation(.spring(response: 0.42, dampingFraction: 0.86), value: isExpanded)
            }
            .overlay(alignment: .bottom) {
                if !isExpanded { bottomFade }
            }
        }
    }

    // MARK: Cover
    @ViewBuilder
    private func cover(geo: GeometryProxy) -> some View {
        let h = geo.size.height * coverHeight

        ZStack {
            // Opaque greedy base — forces the cover to fill h even though the
            // .fit image below is not greedy (otherwise the frame collapses to
            // the image's fitted height).
            theme.surface

            // Fit (not fill) so the whole image shows, never cropped from the top.
            CachedAsyncImage(url: story.imageURL, hue: story.hue, contentMode: .fit)

            // Status-bar legibility scrim.
            VStack {
                LinearGradient(
                    colors: [.black.opacity(0.5), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: safeTop + 40)
                Spacer()
            }
            .allowsHitTesting(false)
        }
        .frame(width: geo.size.width, height: h)
        .clipped()
    }

    private var categoryPill: some View {
        Text(story.category)
            .font(CurioFont.mono(10.5, weight: .semibold))
            .tracking(1.8)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6.5)
            .background(Color.black.opacity(0.55), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
    }

    // MARK: Content
    @ViewBuilder
    private func content(geo: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(story.title)
                .font(CurioFont.display(20, weight: .regular))
                .foregroundColor(theme.text)
                .tracking(-0.2)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 20)

            metaRow
                .padding(.top, 16)

            Rectangle()
                .fill(theme.line)
                .frame(height: 1)
                .padding(.top, 16)

            if isExpanded {
                expandedBody
            } else {
                collapsedBody
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Body — collapsed (preview that fills + fades)
    // Drawn as an overlay on a zero-minimum Color.clear so the preview's tall
    // intrinsic height can't inflate the content and squeeze the cover. It fills
    // whatever space is left and clips (with the bottom fade over it).
    private var collapsedBody: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 18) {
                    dek
                    ArticleBodyView(blocks: previewBlocks)
                }
                .padding(.top, 18)
            }
            .clipped()
            .allowsHitTesting(false)
    }

    // MARK: Body — expanded (full scroll)
    private var expandedBody: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                dek
                ArticleBodyView(blocks: story.blocks)
            }
            .padding(.top, 18)
            .padding(.bottom, safeBottom + 56)
        }
        .scrollIndicators(.hidden)
    }

    // Quiet fade from the collapsed preview into the background.
    private var bottomFade: some View {
        LinearGradient(
            colors: [theme.surface.opacity(0), theme.surface],
            startPoint: .top, endPoint: .bottom
        )
        .frame(height: 130)
        .allowsHitTesting(false)
    }

    // Standfirst / dek under the meta row.
    private var dek: some View {
        Text(story.summary)
            .font(CurioFont.body(16.5, weight: .medium))
            .foregroundColor(theme.text.opacity(0.9))
            .lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var previewBlocks: [ArticleBlock] {
        Array(story.blocks.prefix(3))
    }

    // MARK: Meta + reactions
    private var metaRow: some View {
        HStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(theme.elevated)
                    .frame(width: 32, height: 32)
                Text(story.mono)
                    .font(CurioFont.body(11.5, weight: .bold))
                    .foregroundColor(theme.text)
            }

            Text(story.source)
                .font(CurioFont.body(14, weight: .semibold))
                .foregroundColor(theme.text)
                .padding(.leading, 9)

            Circle()
                .fill(theme.faint)
                .frame(width: 3, height: 3)
                .padding(.horizontal, 8)

            Text(story.readTime)
                .font(CurioFont.body(13.5))
                .foregroundColor(theme.faint)

            Spacer(minLength: 12)

            Button(action: like) {
                HStack(spacing: 6) {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(isLiked ? theme.accent : theme.icon)
                        .scaleEffect(likeBump)
                    Text(formatCount(likeCount))
                        .font(CurioFont.body(13.5, weight: .medium))
                        .foregroundColor(theme.sub)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            .buttonStyle(.plain)

            Button(action: onSave) {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isSaved ? theme.accent : theme.icon)
            }
            .buttonStyle(.plain)
            .padding(.leading, 18)
        }
    }

    // MARK: Interactions
    private func toggleExpand() {
        Haptics.soft()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            onExpandToggle()
        }
    }

    private func like() {
        onLike()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { likeBump = 1.45 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { likeBump = 1 }
        }
    }

    private func formatCount(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fk", Double(n) / 1000.0) : "\(n)"
    }
}

#Preview {
    StoryCardView(
        story: sampleStories[2],
        isExpanded: false,
        isLiked: false,
        isSaved: false,
        likeCount: 2104,
        onExpandToggle: {}, onLike: {}, onSave: {}
    )
    .environment(\.theme, .dark)
    .preferredColorScheme(.dark)
}
