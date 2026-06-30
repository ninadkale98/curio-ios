# Curio — Claude Context

Auto-loaded every session. This is the single source of truth; `HANDOFF.md` has the long-form story.

## What this is
**Curio** — a premium, editorial **TikTok/Instagram-style vertical news reel** in **SwiftUI**
(iOS 17+, Xcode 15+; built with Xcode 26). Dark-mode only. Cool-blue accent (`#6AA0FF`).
Funded startup product — design quality bar is high ("simple yet premium").

## Build & run
- Open `Curio.xcodeproj` (scheme `Curio`). Bundle id `com.curio.newsreel`.
- Simulator: `xcrun xcodebuild -project Curio.xcodeproj -scheme Curio -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
- ⚠️ **iOS builds/archives/TestFlight require macOS + Xcode.** A Linux cowork/cloud env can edit
  code, commit, and push, but CANNOT compile/archive/upload — do those on a Mac (or macOS CI).

## Architecture (MVVM-lite, API-ready)
| File (`Curio/`) | Role |
|---|---|
| `NewsReelApp.swift` | `@main`. Registers bundled fonts + configures URLCache at launch. |
| `FeedView.swift` | Full-screen vertical paging reel. Owns `expandedID` (inline expand) + `detailStory`. |
| `StoryCardView.swift` | Reel card: cover, category pill, title, meta+reactions, collapsed/expanded body. |
| `DetailView.swift` | Simple typography-first long-form reader (no image/chrome/AI) + `DetailArticleView`. |
| `ArticleBodyView.swift` | Compact block renderer for the card + memoized markdown (`MarkdownCache`). |
| `Models.swift` | `Story`/`ArticleBlock`/`Prompt` — all `Codable`, block uses a `"type"` discriminator. |
| `NewsService.swift` | `NewsService` protocol + `MockNewsService` + `@Observable FeedViewModel`. **API seam.** |
| `ImageCache.swift` | `CachedAsyncImage` + NSCache(memory)+URLCache(disk). No GeometryReader inside (intentional). |
| `SampleData.swift` | 5 original editorial stories (every block type). |
| `Theme.swift` | `Palette` dark/light, `CurioFont` (Schibsted Grotesk + Hanken Grotesk), `Color(hex:)`, `Haptics`, `SafeArea`, safe-area env keys. |
| `Fonts/` | Bundled `.ttf` (Schibsted Grotesk + Hanken Grotesk), registered at runtime via `AppFonts.register()`. |

## Interactions (as the user defined them)
- **Feed**: one full-screen reel card per page (Instagram-style).
- **Double-tap** a card → expand/collapse the article **inline** (cover shrinks, body scrolls, paging locks).
- **Swipe-left** → opens the dedicated `DetailView` (simple premium long-form reader). Dismiss with swipe-right.
- **Swipe-right** on a card → **reserved** (no-op stub, `onSwipeRight`).
- Removed by request: the right-edge page rail, "CONTINUE READING" affordance, and the **entire AI/chat feature** (ChatView deleted; `Story.chatIntro`/`prompts` remain as unused data).

## Current state / open issue
- App is live on **TestFlight** (App Store Connect app id `6785755951`, "Curio News Reel").
- **Open:** full-screen paging. On a real iPhone 16 each card was short and the next peeked, though the
  simulator looked fine. Latest build (**build 4**) uses the canonical pattern: `.ignoresSafeArea()` on the
  feed's `GeometryReader` so `proxy.size` is the full screen directly, each card `.frame(width:height:)` to
  `proxy.size`, and notch insets read from the window via `SafeArea.insets()`. A tiny **temp debug readout**
  (bottom-right, e.g. `h852 w393 t59 b34`) is on screen to confirm device dimensions — **remove it** once
  paging is confirmed on device (in `FeedView.body`, the `.overlay(alignment: .bottomTrailing)` block).

## TestFlight pipeline (WORKING — macOS only)
- **Team ID: `XUNGZGDFQL`** (paid). NOT `Q2BKSD85WV` (leftover personal team → "No Account for Team").
- App Store Connect API key (App Manager/Admin). **Secrets live OUTSIDE the repo and are gitignored:**
  - `~/.appstoreconnect/private_keys/AuthKey_DN354DXRVM.p8` (Key `DN354DXRVM`, Issuer `b3fd1580-7cd1-45ae-bd12-42b56b38371d`)
  - `~/.appstoreconnect/fastlane_key.json` (same key, embedded). Fastfile reads `ASC_KEY_ID/ISSUER_ID/KEY_PATH` env with these as defaults.
- Distribution signing in a dedicated keychain `curiobuild.keychain` (pw `curiobuild`), identity
  "Apple Distribution: Ninad Kale (XUNGZGDFQL)", profile "com.curio.newsreel AppStore".
- **xcodebuild automatic signing does NOT work here** — use **manual** signing (profile from fastlane `sigh`).
  fastlane lanes: `setup` (bundle id + checks app record), `builds` (list build states).
- **App record creation is NOT possible via API** (`apps` forbids CREATE) — do it once in the ASC web UI.
- Release a new build (bump `CURRENT_PROJECT_VERSION` in `project.pbxproj` first):
  ```bash
  security unlock-keychain -p curiobuild curiobuild.keychain
  rm -rf build/Curio.xcarchive build/ipa
  xcrun xcodebuild -project Curio.xcodeproj -scheme Curio -configuration Release \
    -destination 'generic/platform=iOS' -archivePath build/Curio.xcarchive archive \
    CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=XUNGZGDFQL \
    CODE_SIGN_IDENTITY="Apple Distribution" PROVISIONING_PROFILE_SPECIFIER="com.curio.newsreel AppStore"
  xcrun xcodebuild -exportArchive -archivePath build/Curio.xcarchive -exportPath build/ipa -exportOptionsPlist ExportOptions.plist
  xcrun altool --upload-app -f build/ipa/Curio.ipa -t ios --apiKey DN354DXRVM --apiIssuer b3fd1580-7cd1-45ae-bd12-42b56b38371d
  ```

## Hard-won gotchas (don't relearn)
1. **SourceKit lies** — the editor shows many false "Cannot find X in scope" errors (single-file analysis). `xcodebuild` is truth.
2. **Build/install:** `xcrun simctl uninstall com.curio.newsreel` before install (stale dylib otherwise); `clean build` if changes don't show.
3. **Overlay coordinate bug:** a child inside a ZStack/VStack containing a framed+clipped image (`CachedAsyncImage`) renders OFF-SCREEN. Put pill/fades on the **card's own** `.overlay(alignment:)`.
4. **Safe area:** `GeometryReader.safeAreaInsets` is 0 when the GeometryReader uses `.ignoresSafeArea()`. Read window insets via `SafeArea.insets()` instead (in `Theme.swift`).
5. **Full-screen paging:** `containerRelativeFrame` resolves to safe-area height on-device → short cards. Use `.ignoresSafeArea()` + `.frame(proxy.size)`.
6. Adding a `.swift` file = 4 edits to `Curio.xcodeproj/project.pbxproj` (PBXBuildFile, PBXFileReference, group children, Sources phase).
7. `AttributedString(markdown:)` valid case is `.inlineOnlyPreservingWhitespace`.

## Secrets to re-establish in a NEW environment (cowork/CI)
None are in git. To run the TestFlight pipeline elsewhere (a Mac), recreate:
- `~/.appstoreconnect/private_keys/AuthKey_DN354DXRVM.p8` (the App Store Connect API key .p8), or set `ASC_KEY_PATH`.
- Re-create the distribution keychain via `fastlane run cert`/`sigh` with the key (see HANDOFF.md), or re-import.

## Roadmap (deferred by user)
Real news API (`APINewsService` stub in `NewsService.swift`); likes/saves persistence (SwiftData);
swipe-right action (TBD); infinite-feed pagination. AI/chat intentionally removed.
