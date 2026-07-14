import SwiftUI

// MARK: - RootTabView
// Bottom nav: Today (stories published today) · Explore (everything else,
// so nothing shows twice) · Profile.
// A custom bottom bar, not SwiftUI's native TabView — on iOS 26 TabView's
// chrome defaults to a floating "Liquid Glass" capsule with no public API to
// revert it to a classic flat bar (tabBarMinimizeBehavior only controls
// scroll-triggered minimizing, not the resting shape). Built by hand instead:
// full-width, opaque, hairline divider on top, icon + small label, matching
// Instagram's Reels tab bar shape. Selection is shown via white + fill variant.
//
// All three tabs stay mounted (toggled via opacity/hit-testing, not a
// switch), so each FeedView keeps its scroll position/expanded state across
// tab switches — the same behavior TabView gives for free.
struct RootTabView: View {
    @State private var vm: FeedViewModel
    @State private var auth: AuthViewModel
    @State private var selection = 1

    init() {
        let auth = AuthViewModel()
        _auth = State(initialValue: auth)
        _vm = State(initialValue: FeedViewModel(auth: auth))
    }

    var body: some View {
        ZStack {
            tab(0) {
                FeedView(
                    vm: vm,
                    filter: { Calendar.current.isDateInToday($0.publishedAt) },
                    emptyMessage: "No new stories today yet — check Explore for the rest."
                )
            }
            tab(1) {
                FeedView(
                    vm: vm,
                    filter: { !Calendar.current.isDateInToday($0.publishedAt) },
                    emptyMessage: "You're all caught up — check Today for what's new."
                )
            }
            tab(2) { ProfileView(vm: vm, auth: auth) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CustomTabBar(selection: $selection)
        }
        .preferredColorScheme(.dark)
        // Load here (not just in FeedView's .task) so Profile has stories to
        // filter against even if Today/Explore haven't appeared yet.
        .task {
            await vm.load()
            await auth.restoreSession()
            if auth.isSignedIn { await vm.hydrateEngagement() }
        }
        // Also hydrate the moment someone signs in mid-session (not just on
        // a restored launch) — real likes/saves should sync right away.
        .onChange(of: auth.isSignedIn) { _, isSignedIn in
            guard isSignedIn else { return }
            Task { await vm.hydrateEngagement() }
        }
    }

    @ViewBuilder
    private func tab(_ index: Int, @ViewBuilder content: () -> some View) -> some View {
        content()
            .opacity(selection == index ? 1 : 0)
            .allowsHitTesting(selection == index)
            .zIndex(selection == index ? 1 : 0)
    }
}

// MARK: - CustomTabBar
private struct CustomTabBar: View {
    @Binding var selection: Int
    private let theme: Palette = .dark

    // sun.max reads literally as "today"; sparkles carries the discovery/
    // browse-everything feel for Explore; newspaper felt too close to
    // sun.max's "daily briefing" read once both were on the bar together.
    // symbolVariant(.fill) drives the selected look.
    private let items: [(icon: String, title: String)] = [
        ("sun.max", "Today"),
        ("sparkles", "Explore"),
        ("person.crop.circle", "Profile"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.white.opacity(0.18)).frame(height: 1)

            HStack(spacing: 0) {
                ForEach(items.indices, id: \.self) { i in
                    Button {
                        Haptics.select()
                        selection = i
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: items[i].icon)
                                .symbolVariant(selection == i ? .fill : .none)
                                .font(.system(size: 18, weight: .medium))
                                .scaleEffect(selection == i ? 1.08 : 1)
                            Text(items[i].title)
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundStyle(selection == i ? .white : theme.faint)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: selection)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 4)   // .safeAreaInset already reserves the home-indicator gap below this
        }
        .background(theme.surface)
    }
}

#Preview {
    RootTabView()
}
