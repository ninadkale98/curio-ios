# Curio — Session Handoff

> Read this first. It captures exactly where the project stands, what's in
> progress, the known bugs, and the plan. Written so a fresh session can continue
> with zero re-discovery.

## What Curio is
Premium, editorial **TikTok/Instagram-style vertical news reel** in **SwiftUI**
(iOS 17+, Xcode 15+). Dark-mode only for now. Cool-blue accent. Builds + runs
clean on the **iPhone 17 Pro simulator (iOS 26)**.

- Project root: `/Users/ninad/experiment/Curio_ios/Curio/`
- Open: `Curio.xcodeproj` · Scheme: `Curio` · Bundle id: `com.curio.newsreel`
- Simulator UDID (iPhone 17 Pro): `12423269-ECE9-4311-BBD1-2A68CEB2FAE8`
- DerivedData hash: `Curio-fepvfvlkomoslidcroakzlxxkyup`

## Intended UX (the spec, as clarified by the user)
- **Feed**: full-screen vertical paging reel of cards. Infinite eventually.
- **Reel card** = cover image (top ~42%) → headline → meta+reactions row → description (summary + first few article blocks, faded at bottom).
- **Double-tap** a card → expand the article **inline** (cover shrinks to ~17%, full article scrolls in place). **Double-tap again** → collapse. Scroll locks while expanded.
- **Swipe-left** on a card → opens a **separate detailed "blog" page** (`DetailView`) — an elaborated, artistic long-form version of the same story.
- **Swipe-right** → **reserved** (no-op stub; user will define later).
- **Removed by request**: the right-edge page-position rail, the "CONTINUE READING" affordance, and **the entire AI/chat feature**.
- `DetailView` is a **simple, typography-first reader**: no hero image, no top icons/chrome, no AI. Just eyebrow + title + byline + rule + body. Dismiss with **swipe-right** (no back button by request). Likes/saves animate with haptics.

## CURRENT STATUS (as of handoff)
Everything compiles, **BUILD SUCCEEDED, zero warnings**. Feed + inline-expand + DetailView all wired.

Verified via screenshots:
- ✅ Feed/reel collapsed card (no rail, no affordance) — looks right.
- ✅ Inline expanded article (cover shrinks, full body scrolls, **bold** markdown renders).
- ✅ Chat panel renders (now invoked from DetailView's "Ask AI").
- ✅ `DetailView` — overflow bug FIXED; hero title wraps (3 lines), body wraps in margins, drop-cap renders.

### ✅ DONE — DetailView horizontal overflow (was the prior next step)
Fixed in `DetailView.swift`: the scroll content `VStack` is now pinned with
`.frame(width: geo.size.width, alignment: .leading)`, `hero(width:height:)` takes an
explicit width, and the hero title has `.frame(maxWidth: .infinity, alignment: .leading)`.
Previously the unconstrained title widened the whole scroll view and clipped all body text.

### NEXT — verify the 3 gestures actually fire (build, then test by injecting state)
macOS blocks synthetic taps to the Simulator (osascript err -25204; no cliclick/Quartz),
so verify interactions by **temporarily** defaulting state and screenshotting, then revert:
- Inline expand: temporarily `@State expandedID: String? = "neuro-chips"` in FeedView.
- Detail page: temporarily `@State detailStory: Story? = sampleStories.first` in FeedView.
The gestures themselves are standard SwiftUI in `StoryCardView.horizontalSwipe` /
`.onTapGesture(count: 2)` and compile fine; only their *visual results* need eyeballing.

## File map (all under `Curio/Curio/`)
| File | Role |
|---|---|
| `NewsReelApp.swift` | `@main`. Registers fonts + configures URLCache at launch. |
| `FeedView.swift` | Paging reel. Owns `expandedID` (inline expand) + `detailStory` (blog). Injects safe-area insets. |
| `StoryCardView.swift` | Reel card: cover, pill, title, meta+reactions, collapsed/expanded body. Double-tap = expand; swipe-left = `onOpenDetail`; swipe-right = `onSwipeRight` (reserved). |
| `DetailView.swift` | **The simple long-form reader** (no image/chrome/AI) + `DetailArticleView` (clean blocks: lead, heading, paragraph, left-rule pull-quote, image, table, diagram). |
| `ArticleBodyView.swift` | Compact block renderer used inside the reel card + memoized markdown (`MarkdownCache`). |
| `Models.swift` | `Story`/`ArticleBlock`/`Prompt`/`ChatMessage` — all `Codable`, block has a `"type"` discriminator. `chatIntro`/`prompts` are now UNUSED (AI removed) but kept as harmless data. |
| `NewsService.swift` | `NewsService` protocol + `MockNewsService` + `@Observable FeedViewModel`. **API seam** (`APINewsService` stub commented). |
| `ImageCache.swift` | `CachedAsyncImage` + NSCache(memory)+URLCache(disk) loader. **No GeometryReader inside (intentional).** |
| `SampleData.swift` | 5 original editorial stories, every block type. |
| `Theme.swift` | `Palette` dark/light, `CurioFont`, `Color(hex:)`, `Haptics`, safe-area env keys, `AppFonts.register()`. |
| `Fonts/` | Schibsted Grotesk + Hanken Grotesk `.ttf` (bundled, runtime-registered). |

## HARD-WON GOTCHAS (do not relearn these)
1. **SourceKit lies.** The editor shows hundreds of "Cannot find X in scope" / "No such
   module UIKit" errors — they're single-file/indexer artifacts. `xcodebuild` is the
   source of truth. Ignore the red squiggles.
2. **Build/install workflow:** always `xcrun simctl uninstall com.curio.newsreel` BEFORE
   install or you may run a stale dylib. If changes don't appear, do `clean build`. The
   Xcode GUI being open contends with CLI builds.
3. **Overlay coordinate bug (cost ~10 builds):** a child placed inside a ZStack/VStack that
   contains a *framed+clipped image* (CachedAsyncImage) renders OFF-SCREEN — padding/offset
   get corrupted. **Fix pattern:** put such overlays (category pill, fades) on the **card's
   own `.overlay(alignment:)`**, never inside the cover/content stacks. This is why the pill
   and fade are on the card body.
4. **Safe-area = 0 bug:** `proxy.safeAreaInsets` returns **zero** if its `GeometryReader`
   has `.ignoresSafeArea()`. FeedView's root GeometryReader must NOT ignoreSafeArea; the
   inner ScrollView/pageBg go full-bleed themselves. Insets flow via `@Environment(\.safeTop/safeBottom)`.
5. `AttributedString(markdown:)` valid syntax case is `.inlineOnlyPreservingWhitespace`
   (NOT `.inlinesOnly`).
6. Adding a new `.swift` file requires **4 edits** to `Curio.xcodeproj/project.pbxproj`
   (PBXBuildFile, PBXFileReference, the Curio PBXGroup children, PBXSourcesBuildPhase).
   Use the existing `AA0023…`/`AB0023…` (DetailView) block as the template.

## Build / run commands
```bash
SIM="12423269-ECE9-4311-BBD1-2A68CEB2FAE8"
APP="/Users/ninad/Library/Developer/Xcode/DerivedData/Curio-fepvfvlkomoslidcroakzlxxkyup/Build/Products/Debug-iphonesimulator/Curio.app"
cd /Users/ninad/experiment/Curio_ios/Curio
xcrun xcodebuild -project Curio.xcodeproj -scheme Curio -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug build \
  2>&1 | grep -E "(error:|warning:|BUILD SUCCEEDED|BUILD FAILED)" | grep -v AppIntents | sort -u
xcrun simctl boot "$SIM" 2>/dev/null; open -a Simulator
xcrun simctl uninstall "$SIM" com.curio.newsreel 2>/dev/null
xcrun simctl install "$SIM" "$APP" && xcrun simctl launch "$SIM" com.curio.newsreel
xcrun simctl io "$SIM" screenshot /tmp/curio.png   # then Read the PNG
```

## Future roadmap (the 4 mocked seams + extras)
1. **Real news API** → implement `APINewsService` in `NewsService.swift` (stub there);
   JSON already matches `Codable Story`. Pass it to `FeedViewModel(service:)`.
2. **AI/chat** → REMOVED by user request (ChatView.swift deleted). If reinstated later,
   `Story.chatIntro`/`prompts` are still in the model. Don't re-add unless asked.
3. **Likes/saves persistence** → `liked`/`saved` Sets in `FeedViewModel`; back with
   SwiftData (`@Model`) or a sync endpoint; hydrate in `load()`.
4. **Image pipeline** → already cached; add prefetch/blur-hash if desired.
5. **Swipe-right action** → currently a reserved no-op (`onSwipeRight`); user will specify.
6. **DetailView polish** → after the overflow fix: consider parallax hero, reading
   progress bar, share, and richer pull-quote/figure treatments.
7. Infinite feed → paginate `FeedViewModel.load()` (append pages as the user nears the end).

## TestFlight / distribution (WORKING — repeatable)
- **Team ID: `XUNGZGDFQL`** (Ninad Kale, paid). NOT `Q2BKSD85WV` (a leftover personal team — caused "No Account for Team").
- API key: `~/.appstoreconnect/private_keys/AuthKey_DN354DXRVM.p8` (Key `DN354DXRVM`, Issuer `b3fd1580-7cd1-45ae-bd12-42b56b38371d`). fastlane JSON (with embedded `key`): `~/.appstoreconnect/fastlane_key.json`.
- App record: **Curio News Reel**, App Store Connect id `6785755951`, bundle `com.curio.newsreel`.
- Distribution signing assets live in a dedicated keychain: `curiobuild.keychain` (password `curiobuild`), identity "Apple Distribution: Ninad Kale (XUNGZGDFQL)". App Store profile "com.curio.newsreel AppStore".
- **xcodebuild automatic signing does NOT work here** (won't use the API key for the archive). Use **manual signing** with the profile, created via fastlane `sigh`/`cert` (Fastfile lanes `setup`/`builds`).
- App record creation is NOT possible via API (`apps` resource forbids CREATE) — must be done in the ASC web UI once per app.
- Releasing a new build (bump `CURRENT_PROJECT_VERSION` first):
  ```bash
  cd /Users/ninad/experiment/Curio_ios/Curio
  security unlock-keychain -p curiobuild curiobuild.keychain
  rm -rf build/Curio.xcarchive build/ipa
  xcrun xcodebuild -project Curio.xcodeproj -scheme Curio -configuration Release \
    -destination 'generic/platform=iOS' -archivePath build/Curio.xcarchive archive \
    CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=XUNGZGDFQL \
    CODE_SIGN_IDENTITY="Apple Distribution" \
    PROVISIONING_PROFILE_SPECIFIER="com.curio.newsreel AppStore"
  xcrun xcodebuild -exportArchive -archivePath build/Curio.xcarchive \
    -exportPath build/ipa -exportOptionsPlist ExportOptions.plist
  xcrun altool --upload-app -f build/ipa/Curio.ipa -t ios \
    --apiKey DN354DXRVM --apiIssuer b3fd1580-7cd1-45ae-bd12-42b56b38371d
  ```
- Current build uploaded: **3** (v1.0). Build 2 had the full-screen paging bug; build 3 fixes it.

## Full-screen paging gotcha (fixed in build 3)
`containerRelativeFrame([.horizontal,.vertical])` resolves to the **safe-area** height on a real
device (full-screen only in the simulator), so each reel card was short and the next peeked. Fix
in `FeedView`: the root GeometryReader (no ignoreSafeArea) gives correct insets; reconstruct the
true screen size `fullH = proxy.size.height + insets.top + insets.bottom`, frame each card to
`(fullW, fullH)` explicitly, and offset the whole stack by `-insets` for full-bleed. Child views
(StoryCardView) no longer call `.ignoresSafeArea()` — the parent handles it.

## Design tokens (dark)
pageBg `#08090B` · surface `#101216` · elevated `#1A1D23` · text `#F4F5F6` ·
sub white@62% · faint white@38% · line white@9% · accent `#6AA0FF`.
Display = Schibsted Grotesk (ExtraBold/Bold/SemiBold). Body = Hanken Grotesk.
