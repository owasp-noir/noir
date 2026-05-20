$version: "2"

namespace example.users

use aws.protocols#restJson1

@restJson1
service UserService {
    version: "2026-05-21"
    operations: [CreateSession, GetUser]
}

@http(method: "POST", uri: "/users/{userId}/sessions", code: 201)
operation CreateSession {
    input: CreateSessionInput
    output: CreateSessionOutput
}

structure CreateSessionInput {
    @httpLabel
    @required
    userId: String

    @httpHeader("X-Session-Token")
    token: String

    @httpQuery("region")
    region: String

    @httpPayload
    body: SessionBody
}

structure CreateSessionOutput {
    sessionId: String
}

structure SessionBody {
    ttl: Integer
    label: String
}

@http(method: "GET", uri: "/users/{userId}")
operation GetUser {
    input: GetUserInput
    output: GetUserOutput
}

structure GetUserInput {
    @httpLabel
    @required
    userId: String

    @httpQuery("verbose")
    verbose: Boolean
}

structure GetUserOutput {
    name: String
    email: String
}
