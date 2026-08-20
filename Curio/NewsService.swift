import Foundation
import Observation

// MARK: - News Service (API seam)
// Swap MockNewsService for a real implementation; the rest of the app is agnostic.
// Cursor-paginated (keyset, on published_at) instead of "fetch everything" —
// the story count grows daily forever, so an unbounded fetch was always going
// to become a problem. `before: nil` = first page (most recent); otherwise
// strictly older than the cursor.
protocol NewsService: Sendable {
    func fetchStories(before cursor: Date?, limit: Int) async throws -> [Story]
}

struct MockNewsService: NewsService {
    func fetchStories(before cursor: Date?, limit: Int) async throws -> [Story] {
        // Structured exactly like a network call so the swap is trivial.
        sampleStories
    }
}

// MARK: - Supabase-backed service
// Fetches the `stories` table over Supabase's auto-generated REST API (PostgREST).
// Uses the ANON key only — safe to embed in a client, since it's scoped by the
// "Public read access" Row Level Security policy (read-only; no insert/update/
// delete). New blogs are added directly in the Supabase dashboard.
struct SupabaseNewsService: NewsService {
    private let baseURL = URL(string: "https://mixkzotcnwvkdvlxhobe.supabase.co/rest/v1/stories")!
    private let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1peGt6b3Rjbnd2a2R2bHhob2JlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI4NzI0ODYsImV4cCI6MjA5ODQ0ODQ4Nn0.3ALwtoucsBj976IN02l4bvkHz2Vaog6fVQaPvxHDVOE"

    func fetchStories(before cursor: Date?, limit: Int) async throws -> [Story] {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        var queryItems = [
            URLQueryItem(name: "order", value: "published_at.desc"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let cursor {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            queryItems.append(URLQueryItem(name: "published_at", value: "lt.\(iso.string(from: cursor))"))
        }
        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            // Postgres timestamptz comes back as ISO8601 WITH fractional
            // seconds — the default ISO8601DateFormatter rejects that unless
            // told to expect it.
            let withFractional = ISO8601DateFormatter()
            withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFractional.date(from: raw) { return date }
            let plain = ISO8601DateFormatter()
            if let date = plain.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(raw)")
        }
        return try decoder.decode([Story].self, from: data)
    }
}

// MARK: - Feed View Model
@MainActor
@Observable
final class FeedViewModel {
    enum LoadState: Equatable {
        case idle, loading, loaded, failed(String)
    }

    private(set) var stories: [Story] = []
    private(set) var state: LoadState = .idle
    private(set) var hasMore = true
    private(set) var isLoadingMore = false

    private static let initialPageSize = 150
    private static let pageSize = 100

    // Local optimistic state, persisted to Supabase per-user via
    // EngagementService when signed in (see hydrateEngagement/toggleLike/
    // toggleSave). Stays local-only and resets each launch while signed
    // out — sign-in isn't required to use the feed yet.
    var liked: Set<String> = []
    var saved: Set<String> = []

    // Snapshot of `liked` right after hydration. story.likes from the server
    // already reflects this snapshot (a trigger keeps it live), so likeCount
    // only needs to add the *delta* since then — adding a flat +1 whenever
    // `liked` contains the id would double-count a like the server already
    // baked into story.likes.
    private var likedAtLoad: Set<String> = []

    private let service: NewsService
    private let engagement = EngagementService()
    private let auth: AuthViewModel?

    init(service: NewsService = SupabaseNewsService(), auth: AuthViewModel? = nil) {
        self.service = service
        self.auth = auth
    }

    func load() async {
        switch state {
        case .loading, .loaded: return   // already have stories — Today/Explore share this vm
        case .idle, .failed: break
        }
        state = .loading
        do {
            let page = try await service.fetchStories(before: nil, limit: Self.initialPageSize)
            stories = page
            hasMore = page.count == Self.initialPageSize
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Fetches the next older page and appends it — call when the reel nears
    /// the end of what's currently loaded (infinite scroll). The story count
    /// grows every day forever, so this (not a one-shot fetch-everything) is
    /// what keeps memory bounded regardless of how large the table gets.
    func loadMore() async {
        guard hasMore, !isLoadingMore, let cursor = stories.last?.publishedAt else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await service.fetchStories(before: cursor, limit: Self.pageSize)
            stories.append(contentsOf: page)
            hasMore = page.count == Self.pageSize
        } catch {
            // Silent — the reel just stops growing for now; the next
            // near-end trigger retries automatically. A background
            // pagination fetch failing shouldn't surface a disruptive error.
        }
    }

    /// Pulls the signed-in user's real likes/saves from Supabase. Call after
    /// a fresh sign-in or a restored session — a no-op while signed out.
    func hydrateEngagement() async {
        guard let token = auth?.session?.accessToken else { return }
        async let likedIDs = try? engagement.fetchLiked(accessToken: token)
        async let savedIDs = try? engagement.fetchSaved(accessToken: token)
        if let likedIDs = await likedIDs {
            liked = likedIDs
            likedAtLoad = likedIDs
        }
        if let savedIDs = await savedIDs { saved = savedIDs }
    }

    // MARK: Engagement
    func isLiked(_ id: String) -> Bool { liked.contains(id) }
    func isSaved(_ id: String) -> Bool { saved.contains(id) }

    func likeCount(for story: Story) -> Int {
        let wasLikedAtLoad = likedAtLoad.contains(story.id)
        let isLikedNow = liked.contains(story.id)
        let delta = (isLikedNow ? 1 : 0) - (wasLikedAtLoad ? 1 : 0)
        return story.likes + delta
    }

    func toggleLike(_ id: String) {
        let nowLiked = !liked.contains(id)
        if nowLiked { liked.insert(id); Haptics.pop() } else { liked.remove(id) }

        guard let session = auth?.session else { return }   // signed out — local only
        Task {
            do {
                if nowLiked {
                    try await engagement.like(storyID: id, userID: session.userID, accessToken: session.accessToken)
                } else {
                    try await engagement.unlike(storyID: id, accessToken: session.accessToken)
                }
            } catch {
                // Write didn't persist — undo the optimistic update.
                if nowLiked { liked.remove(id) } else { liked.insert(id) }
            }
        }
    }

    func toggleSave(_ id: String) {
        let nowSaved = !saved.contains(id)
        if nowSaved { saved.insert(id) } else { saved.remove(id) }
        Haptics.select()

        guard let session = auth?.session else { return }
        Task {
            do {
                if nowSaved {
                    try await engagement.save(storyID: id, userID: session.userID, accessToken: session.accessToken)
                } else {
                    try await engagement.unsave(storyID: id, accessToken: session.accessToken)
                }
            } catch {
                if nowSaved { saved.remove(id) } else { saved.insert(id) }
            }
        }
    }
}
