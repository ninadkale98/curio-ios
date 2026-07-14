import Foundation

// MARK: - EngagementService
// Real per-user likes/saves, hand-rolled REST against Supabase's PostgREST —
// same style as NewsService.swift. RLS on the likes/saves tables scopes every
// request to the signed-in user, so these calls always carry the user's own
// access token (never the anon key alone, never service_role).
struct EngagementService {
    private let baseURL = URL(string: "https://mixkzotcnwvkdvlxhobe.supabase.co/rest/v1")!
    private let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1peGt6b3Rjbnd2a2R2bHhob2JlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI4NzI0ODYsImV4cCI6MjA5ODQ0ODQ4Nn0.3ALwtoucsBj976IN02l4bvkHz2Vaog6fVQaPvxHDVOE"

    func fetchLiked(accessToken: String) async throws -> Set<String> {
        try await fetchStoryIDs(table: "likes", accessToken: accessToken)
    }

    func fetchSaved(accessToken: String) async throws -> Set<String> {
        try await fetchStoryIDs(table: "saves", accessToken: accessToken)
    }

    func like(storyID: String, userID: String, accessToken: String) async throws {
        try await insert(table: "likes", storyID: storyID, userID: userID, accessToken: accessToken)
    }

    func unlike(storyID: String, accessToken: String) async throws {
        try await delete(table: "likes", storyID: storyID, accessToken: accessToken)
    }

    func save(storyID: String, userID: String, accessToken: String) async throws {
        try await insert(table: "saves", storyID: storyID, userID: userID, accessToken: accessToken)
    }

    func unsave(storyID: String, accessToken: String) async throws {
        try await delete(table: "saves", storyID: storyID, accessToken: accessToken)
    }

    // MARK: Private
    private func fetchStoryIDs(table: String, accessToken: String) async throws -> Set<String> {
        var components = URLComponents(url: baseURL.appendingPathComponent(table), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "select", value: "story_id")]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let rows = try JSONDecoder().decode([StoryIDRow].self, from: data)
        return Set(rows.map(\.storyID))
    }

    private func insert(table: String, storyID: String, userID: String, accessToken: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent(table))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=ignore-duplicates", forHTTPHeaderField: "Prefer")   // idempotent re-like/re-save
        request.httpBody = try JSONEncoder().encode(["user_id": userID, "story_id": storyID])
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let code = (response as? HTTPURLResponse)?.statusCode, (200...299).contains(code) else {
            throw URLError(.badServerResponse)
        }
    }

    private func delete(table: String, storyID: String, accessToken: String) async throws {
        var components = URLComponents(url: baseURL.appendingPathComponent(table), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "story_id", value: "eq.\(storyID)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "DELETE"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let code = (response as? HTTPURLResponse)?.statusCode, (200...299).contains(code) else {
            throw URLError(.badServerResponse)
        }
    }

    private struct StoryIDRow: Decodable {
        let storyID: String
        enum CodingKeys: String, CodingKey { case storyID = "story_id" }
    }
}
