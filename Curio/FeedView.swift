import SwiftUI
import UIKit

// MARK: - VerticalPagerController
// A raw UIScrollView we create and fully own — the definitive fix after a long
// chase. Two things had to be true at once and only this gives both:
//
//  1. Paging geometry: isPagingEnabled pages by the scroll view's OWN bounds
//     (the full screen), and contentInsetAdjustmentBehavior = .never means no
//     safe-area inset can shift the content.
//  2. No cross-page bleed: each page host CLIPS to its bounds. The real paging
//     bug was StoryCardView's collapsed preview overflowing its frame, and
//     without clipping the NEXT card's cover bled into the current card.
//
// Native pan drives scrolling. Velocity-based snapping + a fixed-duration
// animation give the crisp TikTok feel. contentKey lets us skip rootView churn
// when only the (unrelated) detail transition is animating.
final class VerticalPagerController: UIViewController, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    private let scrollView = UIScrollView()
    private var hosts: [UIHostingController<AnyView>] = []
    private var lastSize: CGSize = .zero
    private var lastKey = ""
    private(set) var currentPage = 0
    var onPageSettled: (Int) -> Void = { _ in }
    var onOpenPanChanged: (CGFloat) -> Void = { _ in }   // horizontal translation.x (negative = opening)
    var onOpenPanEnded: (CGFloat, CGFloat) -> Void = { _, _ in }  // translation.x, velocity.x

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        overrideUserInterfaceStyle = .dark

        scrollView.isPagingEnabled = false           // we snap by velocity ourselves
        scrollView.decelerationRate = .fast
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.isDirectionalLockEnabled = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.delaysContentTouches = false
        scrollView.bounces = true
        scrollView.backgroundColor = .clear
        scrollView.delegate = self
        view.addSubview(scrollView)

        // Horizontal swipe-to-open lives here, in UIKit, so it can be gated to
        // begin ONLY for a leftward-horizontal drag — vertical scrolls then never
        // contend with it (a SwiftUI gesture on the cards could not do this).
        let openPan = UIPanGestureRecognizer(target: self, action: #selector(handleOpenPan(_:)))
        openPan.delegate = self
        scrollView.addGestureRecognizer(openPan)
    }

    @objc private func handleOpenPan(_ g: UIPanGestureRecognizer) {
        let tx = g.translation(in: view).x
        switch g.state {
        case .began, .changed:
            onOpenPanChanged(tx)
        case .ended, .cancelled, .failed:
            onOpenPanEnded(tx, g.velocity(in: view).x)
        default:
            break
        }
    }

    // Only begin for a clearly-horizontal leftward drag → vertical scroll wins
    // cleanly, no race.
    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard let pan = g as? UIPanGestureRecognizer else { return true }
        let v = pan.velocity(in: view)
        return v.x < 0 && abs(v.x) > abs(v.y) * 1.2
    }

    // Coexist with the scroll view's own pan (and the cards' taps).
    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    func setPages(_ pages: [AnyView], key: String) {
        if hosts.count == pages.count {
            guard key != lastKey else { return }     // nothing card-relevant changed — skip
            lastKey = key
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
            h.safeAreaRegions = []
            h.view.clipsToBounds = true              // never let a card draw outside its own page
            addChild(h)
            scrollView.addSubview(h.view)
            h.didMove(toParent: self)
            return h
        }
        lastKey = key
        lastSize = .zero
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
        scrollView.contentOffset = CGPoint(x: 0, y: CGFloat(currentPage) * size.height)
    }

    // MARK: velocity-based paging + crisp snap (no slow deceleration tail)
    func scrollViewWillEndDragging(_ sv: UIScrollView,
                                   withVelocity velocity: CGPoint,
                                   targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        let h = view.bounds.height
        guard h > 0 else { return }
        let flick: CGFloat = 0.2
        var target = currentPage
        if velocity.y > flick {
            target = currentPage + 1
        } else if velocity.y < -flick {
            target = currentPage - 1
        } else {
            target = Int((targetContentOffset.pointee.y / h).rounded())
        }
        target = max(0, min(hosts.count - 1, target))

        targetContentOffset.pointee = sv.contentOffset
        let dest = CGPoint(x: 0, y: CGFloat(target) * h)
        UIView.animate(withDuration: 0.3, delay: 0,
                       options: [.curveEaseOut, .allowUserInteraction]) {
            sv.contentOffset = dest
        } completion: { _ in
            self.settlePage(target)
        }
    }

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
    let contentKey: String
    let onPageSettled: (Int) -> Void
    let onOpenPanChanged: (CGFloat) -> Void
    let onOpenPanEnded: (CGFloat, CGFloat) -> Void

    func makeUIViewController(context: Context) -> VerticalPagerController {
        let vc = VerticalPagerController()
        vc.onPageSettled = onPageSettled
        vc.onOpenPanChanged = onOpenPanChanged
        vc.onOpenPanEnded = onOpenPanEnded
        vc.setPages(pages, key: contentKey)
        vc.setScrollEnabled(scrollEnabled)
        return vc
    }

    func updateUIViewController(_ vc: VerticalPagerController, context: Context) {
        vc.onPageSettled = onPageSettled
        vc.onOpenPanChanged = onOpenPanChanged
        vc.onOpenPanEnded = onOpenPanEnded
        vc.setPages(pages, key: contentKey)
        vc.setScrollEnabled(scrollEnabled)
    }
}

// MARK: - FeedView
// Shares one FeedViewModel across tabs (Today/Explore) so stories, likes, and
// saves stay in sync; `filter` picks which of vm.stories this instance pages
// through. Embedded inside RootTabView's pinned TabView, so only the top edge
// bleeds under the status bar — the bottom respects the tab bar's own space.
struct FeedView: View {
    let vm: FeedViewModel
    var filter: (Story) -> Bool = { _ in true }
    var emptyMessage: String = "No stories yet"
    @State private var expandedID: String?
    @State private var detailStory: Story?
    @State private var detailProgress: CGFloat = 0    // 0 = reel, 1 = reader open
    @State private var currentPage = 0                // which reel card is showing
    private let theme: Palette = .dark

    private let reveal: Animation = .spring(response: 0.36, dampingFraction: 0.86)

    private var stories: [Story] { vm.stories.filter(filter) }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let topInset = SafeArea.insets().top      // notch/status bar height — constant
            let bottomInset: CGFloat = 16              // breathing room above the pinned tab bar
            let dist = max(size.width * 0.6, 1)        // drag distance that = a full open/close

            ZStack {
                theme.pageBg

                switch vm.state {
                case .idle, .loading:
                    ProgressView().controlSize(.large).tint(theme.accent)
                case .failed(let m):
                    errorView(m)
                case .loaded where stories.isEmpty:
                    emptyView()
                case .loaded:
                    reel(size: size, topInset: topInset, bottomInset: bottomInset, dist: dist)
                        // The reel recedes as the reader comes forward.
                        .scaleEffect(1 - detailProgress * 0.06)
                        .offset(x: -detailProgress * size.width * 0.22)
                        .overlay(
                            Color.black.opacity(detailProgress * 0.5)
                                .ignoresSafeArea(edges: .top)
                                .allowsHitTesting(false)
                        )
                }

                if let story = detailStory {
                    DetailView(
                        story: story,
                        onCloseDragChanged: { tx in closeDragChanged(tx, dist) },
                        onCloseDragEnded:  { tx, pred in closeDragEnded(tx, pred, dist) },
                        onClose: closeReader
                    )
                    .environment(\.safeTop, topInset)
                    .environment(\.safeBottom, bottomInset)
                    .environment(\.theme, theme)
                    .preferredColorScheme(.dark)
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(0.94 + detailProgress * 0.06)
                    .offset(x: (1 - detailProgress) * size.width)
                    .shadow(color: .black.opacity(0.45), radius: 22, x: -10)
                    .zIndex(2)
                }
            }
            .frame(width: size.width, height: size.height)
            .environment(\.safeTop, topInset)
            .environment(\.safeBottom, bottomInset)
        }
        .ignoresSafeArea(edges: .top)
        .environment(\.theme, theme)
        .preferredColorScheme(.dark)
        .task { await vm.load() }
    }

    // MARK: Reel
    private func reel(size: CGSize, topInset: CGFloat, bottomInset: CGFloat, dist: CGFloat) -> some View {
        VerticalPager(
            pages: stories.map { story in
                AnyView(
                    StoryCardView(
                        story: story,
                        isExpanded: expandedID == story.id,
                        isLiked: vm.isLiked(story.id),
                        isSaved: vm.isSaved(story.id),
                        likeCount: vm.likeCount(for: story),
                        onExpandToggle: { toggleExpand(story.id) },
                        onLike: { vm.toggleLike(story.id) },
                        onSave: { vm.toggleSave(story.id) }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .environment(\.safeTop, topInset)
                    .environment(\.safeBottom, bottomInset)
                    .environment(\.theme, theme)
                    .preferredColorScheme(.dark)
                    .ignoresSafeArea(edges: .top)
                )
            },
            scrollEnabled: expandedID == nil && detailStory == nil,
            contentKey: contentKey,
            onPageSettled: { page in currentPage = page; expandedID = nil },
            onOpenPanChanged: { tx in openPanChanged(tx, dist) },
            onOpenPanEnded:  { tx, vx in openPanEnded(tx, vx, dist) }
        )
        .ignoresSafeArea(edges: .top)
    }

    // Changes only when a card's own appearance changes — NOT during the detail
    // transition — so the pager skips rebuilding its hosted cards every frame.
    private var contentKey: String {
        let parts = stories.map { s in
            "\(s.id):\(vm.isLiked(s.id) ? 1 : 0)\(vm.isSaved(s.id) ? 1 : 0):\(vm.likeCount(for: s))"
        }
        return (expandedID ?? "-") + "|" + parts.joined(separator: ",")
    }

    // MARK: Open (swipe-left) — interactive, driven by the pager's UIKit pan
    private func openPanChanged(_ tx: CGFloat, _ dist: CGFloat) {
        guard detailProgress < 1, !stories.isEmpty else { return }
        let story = stories[min(max(currentPage, 0), stories.count - 1)]
        if detailStory?.id != story.id { detailStory = story }
        detailProgress = min(1, max(0, -tx / dist))
    }
    private func openPanEnded(_ tx: CGFloat, _ vx: CGFloat, _ dist: CGFloat) {
        guard detailStory != nil, detailProgress < 1 else { return }
        let p = min(1, max(0, -tx / dist))
        let flick = vx < -650                           // fast leftward flick (pt/s)
        if p > 0.3 || flick {
            Haptics.tap()
            withAnimation(reveal) { detailProgress = 1 }
        } else {
            withAnimation(reveal) { detailProgress = 0 } completion: {
                if detailProgress == 0 { detailStory = nil }
            }
        }
    }

    // MARK: Close (swipe-right) — interactive
    private func closeDragChanged(_ tx: CGFloat, _ dist: CGFloat) {
        guard detailProgress > 0 else { return }
        detailProgress = min(1, max(0, 1 - tx / dist))
    }
    private func closeDragEnded(_ tx: CGFloat, _ predicted: CGFloat, _ dist: CGFloat) {
        let p = min(1, max(0, 1 - tx / dist))
        let flick = predicted > dist * 0.5
        if p < 0.7 || flick {
            closeReader()
        } else {
            withAnimation(reveal) { detailProgress = 1 }
        }
    }
    private func closeReader() {
        Haptics.tap()
        withAnimation(reveal) { detailProgress = 0 } completion: { detailStory = nil }
    }

    // MARK: States
    private func emptyView() -> some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 32))
                .foregroundColor(theme.faint)
            Text(emptyMessage)
                .font(CurioFont.body(15))
                .foregroundColor(theme.sub)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

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
}

#Preview {
    FeedView(vm: FeedViewModel(service: MockNewsService()))
}
