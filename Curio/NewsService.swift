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

// TODO: Real backend — decodes the same Codable `Story` JSON the mock returns.
//
// struct APINewsService: NewsService {
//     let baseURL: URL
//     let session: URLSession = .shared
//     func fetchStories() async throws -> [Story] {
//         let url = baseURL.appending(path: "v1/feed")
//         let (data, response) = try await session.data(from: url)
//         guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
//         return try JSONDecoder().decode([Story].self, from: data)
//     }
// }

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

    init(service: NewsService = MockNewsService()) {
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
