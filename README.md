# Curio — Vertical News Reel (iOS)

Premium, editorial TikTok-style news reader. Full-screen vertical paging,
double-tap to expand articles, swipe right for AI chat. Dark mode, iOS 17+.

## File map

| File | Role |
|---|---|
| `NewsReelApp.swift` | App entry. Registers bundled fonts + configures the disk image cache at launch. |
| `FeedView.swift` | Paging feed. Owns `FeedViewModel`, scroll position, expand/chat UI state, page rail. Injects safe-area insets. |
| `StoryCardView.swift` | Full-screen card: cover, category pill, title, meta + reactions, collapsed/expanded body. Gestures. |
| `ArticleBodyView.swift` | Data-driven block renderer (lead, heading, paragraph, quote, image, table, diagram) + memoized markdown. |
| `ChatView.swift` | Per-story AI chat panel, slides in from trailing edge. |
| `Models.swift` | `Story`, `ArticleBlock`, `Prompt`, `ChatMessage` — all `Codable` for direct API decoding. |
| `NewsService.swift` | `NewsService` protocol + `MockNewsService` + `@Observable FeedViewModel`. **The API seam.** |
| `ImageCache.swift` | `CachedAsyncImage` + two-tier (memory `NSCache` + disk `URLCache`) loader. |
| `SampleData.swift` | 5 original editorial stories, every block type exercised. |
| `Theme.swift` | `Palette` (dark/light), `CurioFont`, `Color(hex:)`, gradient fallback, safe-area env keys, `Haptics`. |
| `Fonts/` | Schibsted Grotesk + Hanken Grotesk `.ttf` (bundled, registered at runtime). |

## Architecture

- **MVVM-lite.** `FeedView` (UI state) → `FeedViewModel` (`@Observable`, data + engagement) → `NewsService` (data source).
- **API-ready by design.** `Story`/`ArticleBlock`/`Prompt` are `Codable` with a typed
  `"type"` discriminator on blocks, so a backend can return the exact JSON the mock returns.
  Swap `MockNewsService` for `APINewsService` (commented stub in `NewsService.swift`) — nothing else changes.
- **Built for scale.** Lazy paging feed, decoded images cached in memory (`NSCache`) and on
  disk (`URLCache`), markdown parsed once and memoized. No per-frame allocations in hot paths.

## Run steps

1. Open `Curio.xcodeproj` in Xcode 15+.
2. Select the **Curio** scheme and any iPhone simulator (iOS 17+).
3. Press **⌘R** to build and run. (CLI: `xcodebuild -scheme Curio -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`)
4. Live Preview: open `FeedView.swift` → **Resume** the canvas.

> No signing needed for Simulator. For a device, set your Team in *Signing & Capabilities*.

## Interactions

- **Double-tap** anywhere on a card — expand / collapse the article (the only trigger, by design).
- **Swipe right** on a card — open the AI chat (gesture only, no button).
- Scroll **locks** while an article is expanded so reading stays focused.
- Like / save spring + haptics; vertical **page rail** on the trailing edge tracks position.

## The 4 mocked pieces (wire up for production)

| # | What | Where | How to wire |
|---|---|---|---|
| 1 | **Stories / API** | `NewsService.swift` | Implement `APINewsService` (stub included); pass it to `FeedViewModel(service:)`. JSON already matches `Codable Story`. |
| 2 | **Image caching** | `ImageCache.swift` | Works today (memory + disk). For blur-hash placeholders or prefetch, extend `ImageLoader`. |
| 3 | **AI chat replies** | `cannedReply(to:)` in `ChatView.swift` (see `// TODO:`) | Join `story.blocks` as context + the question → stream from an LLM; append chunks to `messages`. |
| 4 | **Likes / saves persistence** | `liked` / `saved` in `FeedViewModel` | Back with SwiftData (`@Model`) or a sync endpoint; hydrate in `load()`. |

## Design tokens

- Dark palette: pageBg `#08090B`, surface `#101216`, elevated `#1A1D23`, text `#F4F5F6`, accent `#6AA0FF`.
- Display: **Schibsted Grotesk** (ExtraBold/Bold/SemiBold). Body: **Hanken Grotesk**. Both bundled + runtime-registered.
- Dark-forced for now (`preferredColorScheme(.dark)`); the light `Palette` is kept for a future toggle.

## Notes / gotchas baked into the code

- Overlays (category pill, read affordance) live on the **card's** coordinate space, not
  inside the cover/content — a framed+clipped image otherwise mis-positions child overlays.
- Safe-area insets are read from a root `GeometryReader` (which must **not** `ignoresSafeArea`,
  or `safeAreaInsets` collapses to zero) and injected via `@Environment(\.safeTop/safeBottom)`.
