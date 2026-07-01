import Foundation
import Observation

// MARK: - News Service (API seam)
// Swap MockNewsService for a real implementation; the rest of the app is agnostic.
protocol NewsService: Sendable {
    func fetchStories() async throws -> [Story]
}

struct MockNewsService: NewsService {
    func fetchStories() async throws -> [Story] {
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

    func fetchStories() async throws -> [Story] {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "order", value: "published_at.desc")]

        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([Story].self, from: data)
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

    // Engagement state — in-memory for now.
    // TODO: persist via SwiftData (@Model Engagement) or a backend sync; hydrate on launch.
    var liked: Set<String> = []
    var saved: Set<String> = []

    private let service: NewsService

    init(service: NewsService = SupabaseNewsService()) {
        self.service = service
    }

    func load() async {
        guard state != .loading else { return }
        state = .loading
        do {
            stories = try await service.fetchStories()
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: Engagement
    func isLiked(_ id: String) -> Bool { liked.contains(id) }
    func isSaved(_ id: String) -> Bool { saved.contains(id) }

    func likeCount(for story: Story) -> Int {
        story.likes + (liked.contains(story.id) ? 1 : 0)
    }

    func toggleLike(_ id: String) {
        if liked.contains(id) {
            liked.remove(id)
        } else {
            liked.insert(id)
            Haptics.pop()
        }
    }

    func toggleSave(_ id: String) {
        if saved.contains(id) {
            saved.remove(id)
        } else {
            saved.insert(id)
        }
        Haptics.select()
    }
}
