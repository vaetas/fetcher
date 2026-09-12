import AppKit
import Foundation
import Testing
@testable import fetcher

struct VariableResolverTests {
    let resolver = VariableResolver()

    @Test func substitutesSingleVariable() throws {
        let result = try resolver.resolve("Hello {{name}}", scope: VariableScope(values: ["name": "Ada"]))
        #expect(result.value == "Hello Ada")
        #expect(result.unresolvedNames.isEmpty)
    }

    @Test func substitutesMultipleVariables() throws {
        let result = try resolver.resolve(
            "{{host}}/users/{{id}}",
            scope: VariableScope(values: ["host": "https://api.test", "id": "42"])
        )
        #expect(result.value == "https://api.test/users/42")
    }

    @Test func reportsUndefinedVariable() throws {
        let result = try resolver.resolve("{{missing}}", scope: VariableScope(values: [:]))
        #expect(result.value == "{{missing}}")
        #expect(result.unresolvedNames == ["missing"])
    }

    @Test func detectsCircularReferences() {
        #expect(throws: VariableResolutionError.self) {
            _ = try resolver.resolve("{{a}}", scope: VariableScope(values: ["a": "{{b}}", "b": "{{a}}"]))
        }
    }
}

struct RESTRequestBuilderTests {
    let builder = RESTRequestBuilder()

    @Test func joinsRelativePathWithBaseURL() async throws {
        let draft = sampleDraft(endpoint: "/api/books", baseURL: "http://localhost:8787", query: [
            KeyValueEntry(key: "limit", value: "20"),
        ])
        let (resolved, preview, _) = try await builder.build(draft)
        #expect(resolved.url.absoluteString == "http://localhost:8787/api/books?limit=20")
        #expect(preview.resolvedURL == "http://localhost:8787/api/books?limit=20")
    }

    @Test func absoluteURLOverridesBase() async throws {
        let draft = sampleDraft(
            endpoint: "https://api.example.com/v1/users",
            baseURL: "http://localhost:8787"
        )
        let (resolved, _, _) = try await builder.build(draft)
        #expect(resolved.url.absoluteString == "https://api.example.com/v1/users")
    }

    @Test func encodesPathParameters() async throws {
        let draft = sampleDraft(
            endpoint: "/users/{userId}",
            baseURL: "https://api.example.com",
            path: [KeyValueEntry(key: "userId", value: "a b")]
        )
        let (resolved, _, _) = try await builder.build(draft)
        #expect(resolved.url.absoluteString.contains("/users/a%20b") || resolved.url.path.contains("a"))
    }

    @Test func allowsRepeatedQueryNames() async throws {
        let draft = sampleDraft(
            endpoint: "/tags",
            baseURL: "https://api.example.com",
            query: [
                KeyValueEntry(key: "tag", value: "swift"),
                KeyValueEntry(key: "tag", value: "macos"),
            ]
        )
        let (resolved, _, _) = try await builder.build(draft)
        #expect(resolved.url.absoluteString.contains("tag=swift"))
        #expect(resolved.url.absoluteString.contains("tag=macos"))
    }

    @Test func generatesJSONContentType() async throws {
        let draft = sampleDraft(
            endpoint: "/books",
            baseURL: "https://api.example.com",
            method: "POST",
            bodyMode: .json,
            bodyText: #"{"title":"Dune"}"#
        )
        let (resolved, _, _) = try await builder.build(draft)
        #expect(resolved.headers.contains(where: { $0.0.caseInsensitiveCompare("Content-Type") == .orderedSame && $0.1 == "application/json" }))
        #expect(resolved.body != nil)
    }

    private func sampleDraft(
        endpoint: String,
        baseURL: String,
        method: String = "GET",
        query: [KeyValueEntry] = [],
        path: [KeyValueEntry] = [],
        bodyMode: RESTBodyMode = .none,
        bodyText: String = ""
    ) -> RESTRequestDraft {
        RESTRequestDraft(
            requestID: UUID(),
            projectID: UUID(),
            name: "Test",
            method: method,
            endpoint: endpoint,
            queryParameters: query,
            pathParameters: path,
            headers: [],
            bodyMode: bodyMode,
            bodyText: bodyText,
            authKind: .none,
            bearerToken: nil,
            bearerPrefix: "Bearer",
            basicUsername: nil,
            basicPassword: nil,
            apiKeyName: nil,
            apiKeyValue: nil,
            apiKeyLocation: .header,
            timeoutSeconds: 30,
            redirectPolicy: .follow,
            cookiePolicy: .isolatedEphemeral,
            cachePolicy: .ignoreLocalCache,
            tlsPolicy: .systemDefault,
            projectDefaultHeaders: [],
            projectAuthKind: .none,
            projectBearerToken: nil,
            projectBearerPrefix: "Bearer",
            projectBasicUsername: nil,
            projectBasicPassword: nil,
            projectAPIKeyName: nil,
            projectAPIKeyValue: nil,
            projectAPIKeyLocation: .header,
            baseURL: baseURL,
            variables: [:],
            secretVariables: [:]
        )
    }
}

struct SecretRedactorTests {
    @Test func redactsAuthorization() {
        let headers = [("Authorization", "Bearer secret-token"), ("Accept", "application/json")]
        let redacted = SecretRedactor.redactHeaders(headers)
        #expect(redacted[0].1 == SecretRedactor.redactedPlaceholder)
        #expect(redacted[1].1 == "application/json")
    }

    @Test func detectsSecretsInText() {
        #expect(SecretRedactor.containsSecret("token=abc", secrets: ["abc"]))
        #expect(!SecretRedactor.containsSecret("token=abc", secrets: ["zzz"]))
    }
}

struct AuthStrategyTests {
    @Test func bearerAppliesAuthorizationHeader() async throws {
        var request = URLRequest(url: URL(string: "https://example.com")!)
        var context = ResolvedRequestContext(url: request.url!, headers: [], queryItems: [], secretsUsed: [])
        let strategy = BearerAuthStrategy(token: "secret", prefix: "Bearer")
        try await strategy.apply(to: &request, resolvedContext: &context)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        #expect(context.secretsUsed.contains("secret"))
    }

    @Test func apiKeyCanApplyAsQuery() async throws {
        var request = URLRequest(url: URL(string: "https://example.com/items")!)
        var context = ResolvedRequestContext(url: request.url!, headers: [], queryItems: [], secretsUsed: [])
        let strategy = APIKeyAuthStrategy(name: "api_key", value: "xyz", location: .query)
        try await strategy.apply(to: &request, resolvedContext: &context)
        #expect(request.url?.absoluteString.contains("api_key=xyz") == true)
    }
}

struct ResponseBodyFormatterTests {
    @Test func formatsJSON() throws {
        let data = #"{"b":1,"a":2}"#.data(using: .utf8)!
        let formatted = ResponseBodyFormatter.format(data: data, mimeType: "application/json")
        #expect(formatted.contains("\"a\""))
        #expect(formatted.contains("\"b\""))
    }

    @Test func reportsBinaryFallback() {
        let data = Data([0x00, 0x01, 0x02, 0xFF])
        let formatted = ResponseBodyFormatter.format(data: data, mimeType: "application/octet-stream")
        #expect(formatted.contains("Binary response"))
    }

    @Test func previewLargeTextBody() {
        let payload = String(repeating: "x", count: 120_000)
        let data = Data(payload.utf8)
        let preview = ResponseBodyFormatter.preview(data: data, mimeType: "text/plain")
        #expect(preview?.text.contains("Loading remaining") == true)
    }

    @Test func skipsPrettyPrintForLargeJSON() {
        let json = "{\"value\":\"" + String(repeating: "a", count: 600_000) + "\"}"
        let data = Data(json.utf8)
        let result = ResponseBodyFormatter.formatForDisplay(data: data, mimeType: "application/json")
        #expect(result.skippedPrettyPrint)
        #expect(result.isJSON)
    }
}

struct EditorSearchHighlighterTests {
    @Test func findsCaseInsensitiveMatches() {
        let matches = EditorSearchHighlighter.ranges(of: "error", in: "Error one, another error")
        #expect(matches.count == 2)
    }

    @Test func highlightsActiveMatch() {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let attributed = NSMutableAttributedString(string: "alpha beta alpha")
        attributed.addAttribute(.font, value: font, range: NSRange(location: 0, length: attributed.length))

        let matches = EditorSearchHighlighter.apply(to: attributed, query: "alpha", activeMatchIndex: 1)
        #expect(matches.count == 2)

        let firstColor = attributed.attribute(.backgroundColor, at: matches[0].location, effectiveRange: nil) as? NSColor
        let secondColor = attributed.attribute(.backgroundColor, at: matches[1].location, effectiveRange: nil) as? NSColor
        #expect(firstColor == NSColor.findHighlightColor)
        #expect(secondColor == NSColor.systemOrange.withAlphaComponent(0.55))
    }
}

struct JSONSyntaxHighlighterTests {
    @Test func validatesJSON() {
        #expect(JSONSyntaxHighlighter.isValidJSON(#"{"a":1}"#))
        #expect(!JSONSyntaxHighlighter.isValidJSON("{not json"))
        #expect(!JSONSyntaxHighlighter.isValidJSON(""))
    }

    @Test func highlightsJSONTokens() {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let attributed = JSONSyntaxHighlighter.attributedString(for: #"{"name":"fetcher","count":2,"ok":true,"missing":null}"#, font: font)
        let text = attributed.string
        let nameRange = (text as NSString).range(of: "\"name\"")
        let fetcherRange = (text as NSString).range(of: "\"fetcher\"")
        let countRange = (text as NSString).range(of: "2")
        let trueRange = (text as NSString).range(of: "true")
        let nullRange = (text as NSString).range(of: "null")

        #expect(attributed.attribute(.foregroundColor, at: nameRange.location, effectiveRange: nil) as? NSColor == .systemTeal)
        #expect(attributed.attribute(.foregroundColor, at: fetcherRange.location, effectiveRange: nil) as? NSColor == .systemRed)
        #expect(attributed.attribute(.foregroundColor, at: countRange.location, effectiveRange: nil) as? NSColor == .systemBlue)
        #expect(attributed.attribute(.foregroundColor, at: trueRange.location, effectiveRange: nil) as? NSColor == .systemPurple)
        #expect(attributed.attribute(.foregroundColor, at: nullRange.location, effectiveRange: nil) as? NSColor == .secondaryLabelColor)
    }
}
