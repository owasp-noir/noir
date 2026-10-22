import Vapor

// Service calls hanging off the registered `app` receiver. None of them
// registers a route: `app.client` is Vapor's outbound HTTP client, the rest
// are cache, redis and queue accessors.
struct Notifier {
    func exchangeToken(app: Application) async throws {
        _ = try await app.client.post("https://appleid.apple.com/auth/token") { request in
            request.headers.add(name: .contentType, value: "application/x-www-form-urlencoded")
        }
    }

    func lookup(app: Application) async throws {
        _ = try await app.client.get(URI(string: "https://example.com/feed"))
        _ = try await app.cache.get("last-visit", as: String.self)
        _ = try await app.redis.get("session:abc")
        _ = try await app.queues.queue.get(JobIdentifier(string: "job"))
    }
}
