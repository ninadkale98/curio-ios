import SwiftUI
import UIKit

// MARK: - VerticalPagerController
// A raw UIScrollView we create and fully own — the definitive fix after a long
// chase. Two things had to be true at once and only this gives both:
//
//  1. Paging geometry: isPagingEnabled pages by the scroll view's OWN bounds
//     (the full screen), and contentInsetAdjustmentBehavior = .never on OUR
//     instance means no safe-area inset can shift the content. (SwiftUI's own
//     ScrollView and UIPageViewController kept a 59pt inset we couldn't reach.)
//  2. No cross-page bleed: each page host CLIPS to its bounds. The real bug all
//     along wasn't the scroll container — StoryCardView's collapsed preview
//     overflows its frame, and without clipping the NEXT card's cover bled
//     upward into the current card's bottom (the "¾ + ¼" peek). clipsToBounds
//     on each host contains every card to exactly its own screen.
//
// Native pan drives scrolling (smooth, no SwiftUI gesture arbitration). Expand
// flips isScrollEnabled off so the card's inner article ScrollView takes over.
final class VerticalPagerController: UIViewController, UIScrollViewDelegate {
    private let scrollView = UIScrollView()
    private var hosts: [UIHostingController<AnyView>] = []
    private var lastSize: CGSize = .zero
    private(set) var currentPage = 0
    var onPageSettled: (Int) -> Void = { _ in }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        overrideUserInterfaceStyle = .dark

        // NOTE: isPagingEnabled is intentionally OFF. Apple's built-in paging only
        // flips once you drag past ~half the screen and ignores flick speed, which
        // feels heavy. We snap by VELOCITY in scrollViewWillEndDragging instead, so
        // a short quick flick advances one reel — the TikTok / Reels feel.
        scrollView.isPagingEnabled = false
        scrollView.decelerationRate = .fast                  // snappy settle
        scrollView.contentInsetAdjustmentBehavior = .never   // we own this — never overridden
        scrollView.isDirectionalLockEnabled = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.delaysContentTouches = false              // card taps/swipes engage instantly
        scrollView.bounces = true
        scrollView.backgroundColor = .clear
        scrollView.delegate = self
        view.addSubview(scrollView)
    }

    /// Build the hosted pages once; thereafter just refresh their SwiftUI content
    /// (cheap — SwiftUI diffs the rootView, no rebuild).
    func setPages(_ pages: [AnyView]) {
        if hosts.count == pages.count {
            for (h, p) in zip(hosts, pages) { h.rootView = p }
            return
        }
        hosts.forEach {
            $0.willMove(toParent: nil)
            $0.view.removeFromSuperview()
            $0.removeFromParent()
        }
        hosts = pages.map { page in
            let h = UIHostingController(rootView: page)
            h.view.backgroundColor = .clear
            h.overrideUserInterfaceStyle = .dark
            h.safeAreaRegions = []       // full-screen content; insets arrive via environment
            h.view.clipsToBounds = true  // THE fix: never let a card draw outside its own page
            addChild(h)
            scrollView.addSubview(h.view)
            h.didMove(toParent: self)
            return h
        }
        lastSize = .zero                 // force a fresh layout pass for the new hosts
        viewIfLoaded?.setNeedsLayout()
    }

    func setScrollEnabled(_ enabled: Bool) {
        scrollView.isScrollEnabled = enabled
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scrollView.frame = view.bounds
        let size = view.bounds.size
        guard size.width > 0, size.height > 0, size != lastSize else { return }
        lastSize = size
        for (i, h) in hosts.enumerated() {
            h.view.frame = CGRect(x: 0, y: CGFloat(i) * size.height,
                                  width: size.width, height: size.height)
        }
        scrollView.contentSize = CGSize(width: size.width,
                                        height: size.height * CGFloat(hosts.count))
        // Pin the current card across relayout / rotation.
        scrollView.contentOffset = CGPoint(x: 0, y: CGFloat(currentPage) * size.height)
    }

    // MARK: velocity-based paging (the TikTok feel)
    // Decide the target page from flick speed, not drag distance, then drive the
    // snap with OUR OWN fixed-duration animation. UIScrollView's built-in
    // deceleration approaches a forced target asymptotically — that ease-out tail
    // is the "last part crawls for a second or two" feeling. A definite 0.3s
    // ease-out lands crisply with no tail.
    func scrollViewWillEndDragging(_ sv: UIScrollView,
                                   withVelocity velocity: CGPoint,
                                   targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        let h = view.bounds.height
        guard h > 0 else { return }
        let flick: CGFloat = 0.2   // points/ms — light, so a short quick swipe counts
        var target = currentPage
        if velocity.y > flick {
            target = currentPage + 1
        } else if velocity.y < -flick {
            target = currentPage - 1
        } else {
            target = Int((targetContentOffset.pointee.y / h).rounded())
        }
        target = max(0, min(hosts.count - 1, target))

        // Cancel the built-in deceleration (its asymptotic tail is the slow drift)…
        targetContentOffset.pointee = sv.contentOffset
        // …and snap ourselves with a definite, crisp landing.
        let dest = CGPoint(x: 0, y: CGFloat(target) * h)
        UIView.animate(withDuration: 0.3, delay: 0,
                       options: [.curveEaseOut, .allowUserInteraction]) {
            sv.contentOffset = dest
        } completion: { _ in
            self.settlePage(target)
        }
    }

    // MARK: settle → report the landed page
    // Normal path is the snap animation above; this stays as a harmless fallback.
    func scrollViewDidEndDecelerating(_ sv: UIScrollView) {
        let h = view.bounds.height
        guard h > 0 else { return }
        settlePage(max(0, min(hosts.count - 1, Int((sv.contentOffset.y + h / 2) / h))))
    }
    private func settlePage(_ page: Int) {
        guard page != currentPage else { return }
        currentPage = page
        onPageSettled(page)
    }
}

// MARK: - VerticalPager (SwiftUI bridge)
private struct VerticalPager: UIViewControllerRepresentable {
    let pages: [AnyView]
    let scrollEnabled: Bool
    let onPageSettled: (Int) -> Void

    func makeUIViewController(context: Context) -> VerticalPagerController {
        let vc = VerticalPagerController()
        vc.onPageSettled = onPageSettled
        vc.setPages(pages)
        vc.setScrollEnabled(scrollEnabled)
        return vc
    }

    func updateUIViewController(_ vc: VerticalPagerController, context: Context) {
        vc.onPageSettled = onPageSettled
        vc.setPages(pages)
        vc.setScrollEnabled(scrollEnabled)
    }
}

// MARK: - FeedView
struct FeedView: View {
    @State private var vm = FeedViewModel()
    @State private var expandedID: String?
    @State private var detailStory: Story?
    private let theme: Palette = .dark

    var body: some View {
        let insets = SafeArea.insets()
        ZStack {
            theme.pageBg

            switch vm.state {
            case .idle, .loading:
                ProgressView().controlSize(.large).tint(theme.accent)
            case .failed(let m):
                errorView(m)
            case .loaded:
                VerticalPager(
                    pages: vm.stories.map { story in
                        AnyView(
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
                                onSwipeRight: {}
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .environment(\.safeTop, insets.top)
                            .environment(\.safeBottom, insets.bottom)
                            .environment(\.theme, theme)
                            .preferredColorScheme(.dark)
                            .ignoresSafeArea()
                        )
                    },
                    scrollEnabled: expandedID == nil,
                    onPageSettled: { _ in expandedID = nil }   // revisited card always collapsed
                )
                .ignoresSafeArea()
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
        .ignoresSafeArea()
        .environment(\.theme, theme)
        .preferredColorScheme(.dark)
        .task { await vm.load() }
    }

    // MARK: States
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 32))
                .foregroundColor(theme.faint)
            Text("Couldn't load stories")
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
