import SwiftUI

// MARK: - FeedView
struct FeedView: View {
    @State private var vm = FeedViewModel()

    // Inline-expanded card (double-tap), and the story open in the detailed reader (swipe-left).
    @State private var expandedID: String?
    @State private var detailStory: Story?

    // Dark-forced for now. Light support remains in Palette for a future toggle.
    private let theme: Palette = .dark

    var body: some View {
        GeometryReader { proxy in
            // With .ignoresSafeArea() on this GeometryReader, proxy.size IS the full
            // screen — no reconstruction. Each card framed to proxy.size = one screen.
            let insets = SafeArea.insets()   // notch/home-indicator from the window
            ZStack {
                theme.pageBg

                switch vm.state {
                case .idle, .loading:
                    loadingView
                case .failed(let message):
                    errorView(message)
                case .loaded:
                    feed(size: proxy.size)
                }

                if let story = detailStory {
                    DetailView(story: story) {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) {
                            detailStory = nil
                        }
                    }
                    .transition(.move(edge: .trailing))
                    .zIndex(2)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .environment(\.safeTop, insets.top)
            .environment(\.safeBottom, insets.bottom)
            .overlay(alignment: .bottomTrailing) {
                // TEMP debug — remove once paging is confirmed on device.
                Text("h\(Int(proxy.size.height)) w\(Int(proxy.size.width)) t\(Int(insets.top)) b\(Int(insets.bottom))")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(5)
            }
        }
        .ignoresSafeArea()
        .environment(\.theme, theme)
        .preferredColorScheme(.dark)
        .task { await vm.load() }
    }

    // MARK: Feed — one full-screen card per page
    private func feed(size: CGSize) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(vm.stories) { story in
                    StoryCardView(
                        story: story,
                        isExpanded: expandedID == story.id,
                        isLiked: vm.isLiked(story.id),
                        isSaved: vm.isSaved(story.id),
                        likeCount: vm.likeCount(for: story),
                        onExpandToggle: { toggleExpand(story.id) },
                        onLike: { vm.toggleLike(story.id) },
                        onSave: { vm.toggleSave(story.id) },
                        onOpenDetail: { openDetail(story) },
                        onSwipeRight: { /* TODO: reserved for a future gesture action */ }
                    )
                    .frame(width: size.width, height: size.height)
                    .id(story.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollDisabled(expandedID != nil)   // lock paging while reading inline
    }

    // MARK: States
    private var loadingView: some View {
        ProgressView()
            .controlSize(.large)
            .tint(theme.accent)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 32))
                .foregroundColor(theme.faint)
            Text("Couldn’t load stories")
                .font(CurioFont.display(18, weight: .bold))
                .foregroundColor(theme.text)
            Text(message)
                .font(CurioFont.body(13))
                .foregroundColor(theme.sub)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await vm.load() } }
                .font(CurioFont.body(15, weight: .semibold))
                .foregroundColor(theme.accent)
                .padding(.top, 4)
        }
        .padding(40)
    }

    // MARK: Actions
    private func toggleExpand(_ id: String) {
        expandedID = (expandedID == id) ? nil : id
    }

    private func openDetail(_ story: Story) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) {
            detailStory = story
        }
    }
}

#Preview {
    FeedView()
}
