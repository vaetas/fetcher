# Native macOS API Client Specification

## 1. Product definition

Build a **native macOS-only API client** for manually constructing, sending, inspecting, and organizing API requests.

The product should feel like a first-class Mac application rather than a cross-platform web application embedded in a desktop shell. It should favor Apple frameworks, macOS conventions, keyboard efficiency, low visual noise, and fast navigation. The initial implementation supports **REST over HTTP/HTTPS only**, but the architecture must make **GraphQL and gRPC first-class future protocol types** rather than later hacks layered onto a REST-only data model.

The application is **local-only**:

- No user account.
- No cloud backend.
- No cloud synchronization.
- No collaboration service.
- No analytics or telemetry by default.
- No remote storage of projects, requests, secrets, request bodies, or responses.
- The only network traffic initiated by the app should be:
  1. API requests explicitly triggered by the user.
  2. Optional update checks only if a future distribution mechanism requires them and the user/product owner deliberately enables them.
- Project metadata is persisted locally.
- Secrets are stored in the macOS Keychain rather than ordinary project storage.

The app should be useful for the same broad task category as Postman and Insomnia, but it should deliberately optimize for a **focused, native Mac workflow** instead of attempting to reproduce every collaboration, cloud, automation, or enterprise feature those products expose.

---

## 2. Product goals

### 2.1 Primary goals

1. Make creating and sending a REST request fast enough that the app can replace `curl` for routine manual API exploration.
2. Provide a clear native workspace for grouping related requests by project.
3. Let each project define shared configuration such as a base URL, variables, default headers, and authentication.
4. Make request and response inspection concise and information-dense without becoming visually cluttered.
5. Preserve all user-created data locally and securely.
6. Establish a protocol-oriented architecture that can later add:
   - GraphQL request editing and schema-aware tooling.
   - gRPC unary and streaming calls.
7. Follow current Apple Human Interface Guidelines and macOS 27 design conventions, including Liquid Glass where the system expects it.
8. Be fully usable with mouse/trackpad today and structurally ready for extensive keyboard shortcuts.

### 2.2 Secondary goals

- Fast launch.
- Low idle CPU use.
- Low memory use.
- Native text selection, copy/paste, drag-and-drop, menus, context menus, undo where appropriate, and window behavior.
- Strong accessibility and Full Keyboard Access behavior.
- Easy future support for OpenAPI import.
- Easy future support for request history, code generation, collection import/export, and scripts without redesigning the core model.

### 2.3 Explicit non-goals for the initial release

Do **not** include these in the MVP unless required by another requirement:

- User accounts.
- Team workspaces.
- Cloud synchronization.
- Sharing links.
- Hosted mock servers.
- Cloud environment variables.
- AI features.
- Test runners or CI automation.
- JavaScript pre-request/post-response scripts.
- WebSocket, MQTT, SOAP, SSE, or raw TCP clients.
- GraphQL execution.
- gRPC execution.
- OAuth browser flows.
- Request capture / MITM proxying.
- Automatic code generation.
- OpenAPI import/export.
- Plugin/extension marketplace.
- Multi-platform targets such as iOS, iPadOS, Windows, or Linux.

These can be added later if the underlying architecture remains modular.

---

## 3. Research-backed product decisions

### 3.1 Use SwiftUI as the primary UI framework

Use **SwiftUI** for the application shell, window composition, toolbars, sidebar, inspectors, forms, lists, menus, focus state, search, and most controls.

Reasons:

- Apple’s current macOS design APIs automatically adopt Liquid Glass behavior when standard SwiftUI structures and controls are used.[^1][^2]
- `NavigationSplitView` is specifically designed for two- or three-column navigation in apps where a leading selection drives detail content.[^3]
- Standard toolbar and search APIs automatically integrate with native layout, overflow behavior, window resizing, and macOS conventions.[^4][^5]
- SwiftUI integrates directly with SwiftData for local persistence.[^6]

Use **AppKit selectively**, not as the default UI framework.

### 3.2 Use AppKit/TextKit where a developer tool needs a stronger editor

For JSON, raw text, and later GraphQL/protobuf editing, prefer a native editor based on **`NSTextView` + TextKit** when the basic SwiftUI `TextEditor` becomes insufficient.

Apple explicitly positions `NSTextView` as the principal AppKit text view and TextKit as the system text engine for advanced editing and layout.[^7][^8] WWDC26 includes a TextKit code-editor example with line numbers, confirming that a native code-editor-style experience is an intended use case.[^9]

The MVP can start with a reusable native `CodeTextView` wrapper so the app does not have to migrate away from a simplistic editor after syntax highlighting, line numbers, bracket matching, or large-body handling becomes necessary.

### 3.3 Use the system Liquid Glass implementation, not hand-made blur cards

Liquid Glass should come primarily from:

- standard toolbar material,
- sidebars,
- inspectors,
- menus,
- sheets,
- native controls,
- native search,
- native window chrome.

Apple’s guidance is to use Liquid Glass for the control/navigation layer and keep content areas simpler. Apple engineers explicitly advise against indiscriminately applying glass to ordinary content where there is nothing meaningful underneath to refract.[^10]

Therefore:

- **Do not** place every request section inside custom translucent rounded cards.
- **Do not** use manually layered blur effects to imitate Apple UI.
- **Do not** make the body editor or response editor itself glass.
- **Do** allow the sidebar, toolbar, inspector, and floating controls to gain their system appearance automatically.
- **Do** use `.glassEffect(...)` only for custom controls where a system control cannot express the intended interaction.[^11]

macOS 27 further refines sidebars, toolbar behavior, active-window appearance, borders, and Liquid Glass interaction. Prefer current system components so these improvements are inherited automatically.[^12][^13]

### 3.4 Use a Mac productivity-app layout, not a mobile layout enlarged for desktop

Apple’s macOS HIG recommends using the Mac’s space to present more information with fewer nested levels, supporting resizable windows, menus, keyboard workflows, and customizable workspaces.[^14]

The recommended inspiration is:

- **Proxyman** for high-density source/request/content inspection, side-by-side request/response detail, format-specific preview tabs, customizable panes, and Mac-native behavior.[^15][^16]
- **Nova** for a compact native project sidebar, a focused central workspace, command-driven workflows, and a “native first, power without clutter” philosophy.[^17]
- **TablePlus** for a searchable sidebar, fast switching between saved contexts, recent items, and keyboard-oriented navigation.[^18]

Do not visually clone these apps. Use them as evidence that dense developer tooling can remain recognizably native on macOS.

---

## 4. Platform and technical baseline

### 4.1 Platform

- Target: **macOS 27 and later**.
- IDE: **Xcode 27 or later**.
- Language: Swift version bundled with Xcode 27.
- Concurrency: use modern Swift concurrency (`async`/`await`, actors, `Sendable` discipline).
- UI: SwiftUI.
- Native editor: AppKit `NSTextView` / TextKit where needed.
- Persistence: SwiftData.
- Networking: Foundation `URLSession` for REST.
- Secrets: Security framework / Keychain Services.
- Testing: Swift Testing plus Xcode UI tests where required.
- Package manager: Swift Package Manager only for dependencies that are genuinely required.

### 4.2 Dependency policy

The MVP should use **no third-party dependency unless there is a clear technical advantage that Apple frameworks do not provide**.

Preferred MVP dependency count: **zero**.

Potential later dependencies:

- `grpc-swift-2` and companion packages for gRPC.[^19][^20]
- A standards-compliant GraphQL parser/editor library if building one internally is unjustified.
- An OpenAPI parser if native import is added later.

Do not add a cross-platform UI framework, embedded browser UI, Electron runtime, React Native, Flutter, or a local web server.

---

## 5. Application information architecture

## 5.1 Main window

Use one primary `WindowGroup`.

Recommended high-level layout:

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│ Toolbar: project/request context | environment | Run/Stop | Search | Inspector│
├──────────────────┬───────────────────────────────────────────────────────────┤
│                  │ Request header                                             │
│ Projects /       │ [GET ▾] [ /users/{id} or full URL................] [Send] │
│ Requests         ├───────────────────────────────────────────────────────────┤
│ Sidebar          │ Request editor                                             │
│                  │ Params | Auth | Headers | Body | Settings                  │
│                  │                                                           │
│                  ├───────────────────────────────────────────────────────────┤
│                  │ Response                                                   │
│                  │ Body | Headers | Cookies | Timing | Raw                    │
│                  │                                                           │
└──────────────────┴───────────────────────────────────────────────────────────┘
```

An optional trailing **Inspector** can expose project/request metadata without permanently consuming horizontal space:

```text
┌──────────────┬───────────────────────────────────────┬───────────────────────┐
│ Sidebar      │ Request + response workspace          │ Inspector              │
│              │                                       │ Environment / details  │
└──────────────┴───────────────────────────────────────┴───────────────────────┘
```

Use `NavigationSplitView` for the primary sidebar/detail structure. Apple recommends sidebars for top-level collections and suggests limiting sidebar hierarchy to roughly two levels; deeper structures are better represented with another content column or detail area.[^21]

### 5.2 Sidebar hierarchy

Initial hierarchy:

```text
PROJECTS
▾ My API
    GET    List users
    POST   Create user
    PATCH  Update user

▾ Internal API
    GET    Health
    DELETE Remove cache
```

Rules:

- Projects are top-level expandable groups.
- Requests are second-level items.
- Do not introduce arbitrary folders in MVP.
- Support drag reordering within a project.
- Support project reordering.
- Show HTTP method using a compact label.
- Keep request name primary; endpoint/path is optional secondary text when space allows.
- Use a system search field for project/request filtering.
- Allow sidebar hide/show via native View menu behavior.
- Persist sidebar width and expansion state.

Future optional hierarchy:

```text
Project
  Folder
    Request
```

If folders are added, avoid unbounded tree depth. Limit to project → folder → request unless there is a demonstrated need for deeper nesting.

### 5.3 Toolbar

Keep the toolbar intentionally small. Apple recommends avoiding overcrowded toolbars and allowing the system to manage overflow on macOS.[^4]

Recommended persistent toolbar items:

- Sidebar toggle: system-provided.
- New request.
- Environment picker.
- Run / Stop.
- Search.
- Inspector toggle.

Optional/customizable toolbar items later:

- New project.
- Duplicate request.
- Import.
- Export.
- History.
- Pretty-print body.

Every toolbar action must also exist in the menu bar because macOS users can hide or customize toolbars.[^22]

### 5.4 Request header row

At the top of the detail workspace:

1. Method picker.
2. URL/path field.
3. Send button.
4. While executing:
   - Send becomes Stop.
   - Progress state is visible without modal UI.

Examples:

```text
GET    /users/{{userId}}                         Send
POST   https://api.example.com/v1/users          Send
```

Rules:

- A project may define a base URL.
- If the request URL starts with `/`, resolve it relative to the active project/environment base URL.
- A fully qualified URL overrides the project base URL.
- Invalid URL state should be indicated inline.
- Do not block editing because a URL is incomplete.

### 5.5 Request editor tabs

MVP tabs:

- **Params**
- **Auth**
- **Headers**
- **Body**
- **Settings**

The selected tab is remembered per request or globally; prefer global if users tend to work repeatedly in one mode.

Do not place rarely used transport settings in the main request screen. Put them under Settings or the inspector.

### 5.6 Response region

The response should appear in the same window without a modal.

Recommended response tabs:

- **Body**
- **Headers**
- **Cookies**
- **Timing**
- **Raw**

Response summary row:

```text
200 OK     143 ms     4.8 KB     HTTP/2
```

If no response exists:

- show a restrained empty state,
- explain that sending the request will display the response,
- do not use oversized marketing-style illustrations.

---

## 6. Keyboard and menu architecture

Keyboard support is not required to be complete in the first implementation, but the command architecture must be designed from day one.

Apple’s HIG emphasizes respecting standard shortcuts and supporting Full Keyboard Access on Mac.[^23]

Use SwiftUI `Commands`, `CommandMenu`, `CommandGroup`, and `.keyboardShortcut(...)` rather than ad-hoc global event interception. SwiftUI menu commands automatically expose shortcuts in the menu bar.[^24]

Reserve the following command identifiers now:

| Action | Proposed shortcut | Notes |
|---|---:|---|
| Send request | `⌘↩` | Common developer-tool convention; do not use Return alone |
| Cancel request | `Esc` | Only while request is running |
| New request | `⌘N` | Standard New action |
| New project | `⇧⌘N` | Secondary creation |
| Search requests | `⌘F` | Prefer system search semantics |
| Duplicate request | `⌘D` | Confirm no conflict with current focus context |
| Toggle sidebar | system default | Do not replace standard behavior |
| Toggle inspector | `⌥⌘I` if appropriate | Matches macOS inspector convention |
| Focus URL | configurable later | Avoid colliding with system shortcuts |
| Next/previous request | configurable later | Prefer native command routing |

Architecture requirement:

```swift
enum AppCommandID: Hashable {
    case sendRequest
    case cancelRequest
    case newRequest
    case newProject
    case duplicateRequest
    case toggleInspector
    case focusURL
}
```

Business actions should be callable independently of the views so toolbar buttons, menu items, context menus, and shortcuts all invoke the same command handlers.

---

## 7. Local persistence architecture

### 7.1 Use SwiftData

Use SwiftData for user-created structured data.

Apple describes `ModelContainer` as the component that manages persistent schema storage and migrations, and the framework integrates directly with SwiftUI.[^25] WWDC26 continues to position SwiftData as the modern Apple-native persistence layer for local app state.[^6][^26]

Important:

- Do **not** enable CloudKit.
- Do **not** add iCloud entitlements.
- Configure a purely local model container.
- Keep persistence models separate from networking DTOs.
- Keep persistence models separate from import/export DTOs.

### 7.2 Persistence domains

Persist locally:

- Projects.
- Requests.
- Project environments.
- Non-secret variables.
- Headers.
- Request body text.
- Request-level transport settings.
- UI state that is valuable across launches.
- Optional bounded request history metadata.

Do not persist ordinary network cache data unless intentionally designed.

### 7.3 Secrets

Never store these directly in SwiftData:

- passwords,
- bearer tokens,
- API keys marked secret,
- client-certificate passphrases,
- OAuth refresh/access tokens in future versions.

Store them in the macOS Keychain using Keychain Services. Apple explicitly recommends the keychain for small secrets and encrypted credential storage.[^27][^28]

Persist only a `SecretReference` identifier in SwiftData.

Example:

```swift
struct SecretReference: Codable, Hashable {
    let id: UUID
    let label: String
}
```

Keychain item account/service convention:

```text
service = "<bundle-id>.secret"
account = "<secret-reference-uuid>"
```

### 7.4 Optional request history

History is useful, but unbounded response-body persistence is dangerous.

If history is included in MVP:

- store metadata for the last N executions per request,
- default N = 20,
- body persistence default = disabled or limited by size,
- cap persisted response body, for example 1–5 MB per execution,
- provide Clear History,
- never duplicate secrets into history,
- redact sensitive headers in stored history.

A simpler MVP may show only the latest response in memory and persist no responses.

---

## 8. Domain data model

The model must avoid assuming every future request is REST.

### 8.1 Project

```swift
@Model
final class ProjectRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var sortIndex: Double

    @Relationship(deleteRule: .cascade)
    var requests: [RequestRecord]

    @Relationship(deleteRule: .cascade)
    var environments: [EnvironmentRecord]

    var selectedEnvironmentID: UUID?
}
```

Project responsibilities:

- own requests,
- own environment definitions,
- provide shared base URL,
- provide shared non-secret variables,
- optionally provide default headers,
- optionally provide project-level authentication defaults.

### 8.2 Request record: protocol-neutral root

```swift
enum APIProtocolKind: String, Codable, CaseIterable {
    case rest
    case graphql
    case grpc
}

@Model
final class RequestRecord {
    @Attribute(.unique) var id: UUID
    var projectID: UUID
    var name: String
    var protocolKindRaw: String
    var createdAt: Date
    var updatedAt: Date
    var sortIndex: Double
}
```

Do not add REST-only fields such as `httpMethod` directly to the protocol-neutral root.

### 8.3 REST-specific configuration

```swift
@Model
final class RESTRequestRecord {
    @Attribute(.unique) var requestID: UUID

    var method: String
    var endpoint: String

    var bodyModeRaw: String
    var bodyText: String

    var timeoutSeconds: Double?
    var redirectPolicyRaw: String
    var cookiePolicyRaw: String
    var cachePolicyRaw: String
    var tlsPolicyRaw: String
}
```

Related child records:

```swift
@Model
final class RequestParameterRecord {
    var id: UUID
    var ownerRequestID: UUID
    var kindRaw: String   // query, path, header
    var key: String
    var value: String
    var isEnabled: Bool
    var sortIndex: Double
}

@Model
final class RequestAuthRecord {
    var requestID: UUID
    var authTypeRaw: String
    var nonSecretJSON: Data
    var secretReferenceIDs: [UUID]
}
```

This arrangement allows future protocol-specific models:

```text
RequestRecord
 ├── RESTRequestRecord
 ├── GraphQLRequestRecord
 └── GRPCRequestRecord
```

without forcing GraphQL/gRPC fields into one oversized generic table.

### 8.4 Environment

```swift
@Model
final class EnvironmentRecord {
    @Attribute(.unique) var id: UUID
    var projectID: UUID
    var name: String
    var baseURL: String
    var sortIndex: Double

    @Relationship(deleteRule: .cascade)
    var variables: [EnvironmentVariableRecord]
}
```

Examples:

```text
Development
  baseURL = http://localhost:8787

Staging
  baseURL = https://staging-api.example.com

Production
  baseURL = https://api.example.com
```

### 8.5 Environment variable

```swift
@Model
final class EnvironmentVariableRecord {
    var id: UUID
    var environmentID: UUID
    var key: String
    var value: String?
    var secretReferenceID: UUID?
    var isSecret: Bool
    var isEnabled: Bool
}
```

Variables can be referenced with:

```text
{{variableName}}
```

V1 variable resolution locations:

- endpoint,
- path parameter values,
- query parameter values,
- header names only if explicitly allowed later,
- header values,
- body text,
- auth non-secret fields,
- auth secret values.

Recommended: do **not** allow variable expansion in header names initially; values are enough and safer.

---

## 9. REST request specification

A robust API client needs more than method + URL + body. HTTP semantics include a request method, target URI, header fields, optional content, authentication, redirects, caching, and content negotiation.[^29]

OpenAPI similarly distinguishes path, query, header, and cookie parameters, plus request bodies and security schemes.[^30]

The following model should therefore be the canonical REST request definition.

## 9.1 Request method

MVP standard methods:

- GET
- HEAD
- POST
- PUT
- PATCH
- DELETE
- OPTIONS

Also support:

- custom method string

HTTP method tokens are extensible and case-sensitive at the protocol level, although standardized methods conventionally use uppercase.[^29]

Recommended UI:

```text
[ GET ▾ ]
```

Picker contents:

```text
GET
POST
PUT
PATCH
DELETE
HEAD
OPTIONS
────────
Custom…
```

### Body behavior

Do not hard-block request bodies for GET/HEAD because HTTP implementations can technically represent them, but:

- show no body by default,
- display a subtle warning if a user adds one,
- do not suggest this as ordinary usage.

RFC 9110 notes that GET content has no generally defined semantics and can be rejected by intermediaries.[^29]

---

## 9.2 Endpoint and URL resolution

Support both:

```text
/users
/v1/users/{{userId}}
https://api.example.com/v1/users
```

Resolution algorithm:

1. Resolve environment variables.
2. If endpoint is an absolute `http` or `https` URL:
   - use it directly.
3. Else:
   - obtain active environment base URL,
   - if missing, fall back to project base URL if a project-level default is implemented,
   - join using `URLComponents`-safe logic rather than string concatenation.
4. Apply path parameters.
5. Apply query parameters.
6. Validate the final URL.
7. Produce a `URLRequest`.

Use Foundation `URLComponents` and `URLQueryItem` to avoid manual percent-encoding bugs.

---

## 9.3 Path parameters

Example endpoint:

```text
/users/{userId}/books/{bookId}
```

Path parameter table:

| Enabled | Key | Value |
|---|---|---|
| ✓ | `userId` | `{{userId}}` |
| ✓ | `bookId` | `42` |

Requirements:

- Detect `{name}` placeholders automatically.
- Show missing placeholders as validation warnings.
- Extra path parameter entries not referenced by the endpoint should be shown as unused.
- Percent-encode values as URL path components.
- Never insert path values through naive string interpolation without encoding.

Future OpenAPI import can populate these automatically because OpenAPI explicitly models path parameters.[^30]

---

## 9.4 Query parameters

Table:

| Enabled | Key | Value |
|---|---|---|
| ✓ | `page` | `1` |
| ✓ | `sort` | `createdAt` |
| ☐ | `debug` | `true` |

Requirements:

- Preserve row order.
- Permit repeated names:

```text
tag=swift&tag=macos
```

- Permit empty value:

```text
flag=
```

- Distinguish disabled row from an enabled empty value.
- Show the final encoded query in the URL field or a resolved preview.
- Use `URLQueryItem`.

Postman and Insomnia expose path/query parameters as first-class request fields for the same reason.[^31][^32]

---

## 9.5 Headers

Headers are ordered editable key/value rows with enable/disable state.

Data:

```swift
struct HeaderEntry: Identifiable, Codable {
    var id: UUID
    var name: String
    var value: String
    var isEnabled: Bool
}
```

Requirements:

- Permit custom headers.
- Permit duplicate header names when HTTP semantics allow them.
- Header-name autocomplete for common names:
  - Accept
  - Authorization
  - Content-Type
  - User-Agent
  - If-None-Match
  - If-Modified-Since
  - Cache-Control
  - Origin
  - Referer
- Values can contain environment variables.
- Automatically generated headers must be visible in a resolved preview.
- User-supplied values take precedence over generated defaults where safely possible.
- Do not silently generate `Content-Length`; let URL loading handle transport framing.
- Do not require manual `Host`.
- Do not flatten duplicate headers prematurely in the domain model.

Suggested generated headers:

- `Content-Type: application/json` for JSON body unless user overrides.
- `Content-Type: text/plain; charset=utf-8` for plain text unless user overrides.
- `Authorization` when auth mode requires it.
- API-key header when configured.

Postman similarly distinguishes user-entered and autogenerated headers and lets explicit values override generated ones.[^33]

---

## 9.6 Authentication

MVP auth modes:

1. None
2. Inherit project
3. Bearer Token
4. Basic Auth
5. API Key

### None

No auth-related header or parameter is added.

### Inherit project

Use project/environment default auth configuration.

### Bearer Token

Fields:

```text
Token: [secret]
Prefix: Bearer
```

Generated:

```http
Authorization: Bearer <token>
```

Store token in Keychain.

### Basic Auth

Fields:

```text
Username
Password [secret]
```

Generate HTTP Basic credentials.

Store password in Keychain.

### API Key

Fields:

```text
Key name
Value [secret]
Location: Header | Query
```

Examples:

```http
X-API-Key: ...
```

or:

```text
?api_key=...
```

OpenAPI models API keys in header/query/cookie locations and also supports HTTP auth, mutual TLS, OAuth 2, and OpenID Connect.[^30]

### Deferred auth modes

Architecture must allow later addition of:

- Digest
- OAuth 1
- OAuth 2
- OpenID Connect
- AWS Signature V4
- NTLM / Negotiate
- client certificate / mTLS
- Netrc

Insomnia’s supported auth surface demonstrates why auth should be modeled as a pluggable strategy rather than fields embedded directly into every request.[^34]

Recommended interface:

```swift
protocol RequestAuthenticationStrategy: Sendable {
    var kind: AuthKind { get }
    func apply(
        to request: inout URLRequest,
        resolvedContext: ResolvedRequestContext
    ) async throws
}
```

---

## 9.7 Body

MVP body modes:

- None
- JSON
- Text

Represent body mode explicitly:

```swift
enum RESTBodyMode: String, Codable {
    case none
    case json
    case text
}
```

### JSON body

Requirements:

- Native text editor.
- Monospaced font.
- Syntax highlighting if reasonably implementable in V1.
- Validate JSON locally.
- Show syntax error location.
- “Format JSON” command.
- Do not automatically rewrite valid JSON while the user types.
- Encode as UTF-8 when sending.
- Default `Content-Type` to `application/json` unless overridden.

### Text body

Requirements:

- Raw editable text.
- UTF-8 by default.
- Default `Content-Type` to `text/plain; charset=utf-8` unless overridden.
- Allow user to override Content-Type.

### Deferred body modes

Model the body architecture so these can be added without replacing it:

- `application/x-www-form-urlencoded`
- `multipart/form-data`
- binary
- file
- XML
- GraphQL-specific document mode

Postman supports form data, URL-encoded, raw, and binary bodies; this is a useful future completeness target, but only JSON/text are required initially.[^31]

Recommended future-safe type:

```swift
enum RESTBody {
    case none
    case json(String)
    case text(String, contentType: String?)
    case formURLEncoded([KeyValueEntry])
    case multipart([MultipartPart])
    case binary(Data, filename: String?)
}
```

Persistence may encode the mode and mode-specific payload separately rather than directly persisting an enum with associated values.

---

## 9.8 Cookies

MVP recommendation:

- Display response cookies.
- Do not expose a complex cookie manager yet.
- Avoid silently sharing the system-wide cookie store.
- Use an isolated request-session cookie policy.

Later:

- per-project cookie jar,
- manual cookie editor,
- cookie enable/disable,
- import/export.

`URLSessionConfiguration.ephemeral` provides private in-memory cookie storage and does not persist session-related caches, cookies, or credentials to disk.[^35][^36]

---

## 9.9 Timeout

Request setting:

```text
Timeout: Use project default | Custom
Custom seconds: 30
```

Recommended default: 30 seconds.

Implementation:

- configure `URLRequest.timeoutInterval` or a request-specific session strategy,
- distinguish connection/request timeout from user cancellation in errors.

Do not expose every `URLSessionConfiguration` knob in V1.

---

## 9.10 Redirect policy

MVP options:

- Follow redirects: On (default)
- Follow redirects: Off

Later:

- max redirects,
- preserve method behavior diagnostics,
- redirect chain view.

HTTP redirect handling can modify methods and strip sensitive/content headers depending on status semantics; the response UI should eventually expose the redirect chain for debugging.[^29]

Use `URLSessionTaskDelegate` redirect handling rather than reimplementing HTTP redirect logic.

---

## 9.11 Cache policy

API-testing tools should prioritize determinism over normal browser-like caching.

Recommended MVP default:

```text
Cache: Ignore local cache
```

Options later:

- Use protocol cache policy.
- Reload ignoring local cache.
- Return cache else load.
- Return cache only.

Use an ephemeral session and consider `urlCache = nil` for the main REST executor.

---

## 9.12 TLS and certificate behavior

Default:

- validate server certificates normally,
- require HTTPS for normal public APIs,
- surface TLS failures clearly.

Developer tools sometimes need local/self-signed certificates. Provide an explicit advanced setting later:

```text
TLS validation
◉ System default
○ Allow untrusted certificate for this host
```

This override must be:

- off by default,
- visibly marked insecure,
- host-scoped,
- never silently enabled globally,
- excluded from ordinary production defaults.

Apple notes that manual server-trust handling is useful for development servers with self-signed certificates, but ATS restrictions still apply to ATS-protected domains.[^37]

---

## 9.13 HTTP vs HTTPS and App Transport Security

This is an important product decision for an API-testing app.

ATS normally requires secure `URLSession` connections and blocks insecure public HTTP loads.[^38]

For local development, `NSAllowsLocalNetworking` allows unqualified domains, `.local` domains, and relevant local/IP cases on modern systems.[^39]

However, an API client may legitimately need to test arbitrary public HTTP endpoints. There are two distribution modes:

### Option A — direct/notarized developer distribution: recommended for maximum API-client capability

- App Sandbox on.
- Outgoing network entitlement on.
- `NSAllowsArbitraryLoads = YES` if testing arbitrary insecure HTTP is a hard product requirement.
- Explain the security tradeoff in project documentation.
- Continue to show HTTPS as the normal/recommended path.
- Keep insecure-certificate overrides explicit and scoped.

This provides the behavior developers expect from a general API client.

### Option B — Mac App Store-oriented restrictive build

- Keep ATS enabled.
- Enable `NSAllowsLocalNetworking` for local development endpoints.
- Permit secure HTTPS normally.
- Avoid arbitrary public HTTP unless the App Store justification is accepted.

Apple documents that some ATS exceptions require App Store justification.[^40][^41]

The implementation agent must not work around ATS by unexpectedly switching to low-level sockets solely to bypass platform security. Apple explicitly recommends high-level URL loading in ordinary applications because it provides safer connection handling.[^42]

---

## 9.14 Proxy settings

Defer custom proxy UI from MVP, but reserve the concept in transport settings.

Future modes:

- System proxy.
- No proxy.
- HTTP/HTTPS proxy.
- SOCKS if a suitable native transport supports it cleanly.
- Per-project proxy.

Insomnia exposes proxy configuration because enterprise and local-debug environments often require it.[^43]

Do not implement an intercepting proxy/MITM system as part of this app’s initial scope.

---

## 9.15 HTTP version

Do not expose a “force HTTP/1.1 / HTTP/2 / HTTP/3” selector in MVP.

Let `URLSession` negotiate the protocol.

Capture and display the actual negotiated protocol through `URLSessionTaskMetrics` when available.

HTTP/1.1, HTTP/2, and HTTP/3 share HTTP semantics but use different transport/message encodings.[^29][^44][^45][^46]

Future advanced testing may add transport-version constraints if Foundation exposes a stable, appropriate API.

---

## 10. Request resolution pipeline

Never send directly from SwiftUI field state.

Use a deterministic multi-stage pipeline:

```text
Saved Request
    ↓
Active Project + Environment
    ↓
Variable Resolver
    ↓
Validation
    ↓
URL Builder
    ↓
Header Resolver
    ↓
Authentication Strategy
    ↓
Body Encoder
    ↓
Prepared REST Request
    ↓
URLSession Executor
    ↓
Response Artifact
```

Core types:

```swift
struct RESTRequestDraft: Sendable { ... }

struct ResolvedRESTRequest: Sendable {
    let method: String
    let url: URL
    let headers: [(String, String)]
    let body: Data?
    let timeout: TimeInterval
    let redirectPolicy: RedirectPolicy
    let tlsPolicy: TLSPolicy
}

struct PreparedRequestPreview: Sendable {
    let resolvedURL: String
    let headers: [(String, String)]
    let bodyPreview: String?
    let warnings: [RequestWarning]
}
```

The UI should be able to show a **resolved preview** before or after sending so the user can see what variables and generated auth/header fields produced.

---

## 11. Networking implementation

## 11.1 REST transport

Use Foundation:

- `URLRequest`
- `URLSession`
- `URLSessionConfiguration`
- `HTTPURLResponse`
- `URLSessionTaskDelegate`
- `URLSessionDelegate`
- `URLSessionTaskMetrics`

Apple’s `URLSessionConfiguration` supports timeout, cache, cookies, credentials, TLS behavior, and connection policies.[^47]

### Recommended configuration

Start from:

```swift
let configuration = URLSessionConfiguration.ephemeral
configuration.urlCache = nil
configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
configuration.waitsForConnectivity = false
configuration.httpShouldSetCookies = true
configuration.urlCredentialStorage = nil
```

Rationale:

- no shared persistent cache,
- no shared persistent credential store,
- isolated cookies,
- deterministic API testing,
- avoids unexpected use of credentials stored by other apps/system components.

Apple documents that ephemeral sessions keep caches, cookies, and credentials in memory rather than persistent session storage.[^35]

### Session lifecycle

Use a small `RESTSessionManager` actor.

Possible model:

```swift
actor RESTSessionManager {
    private var sessions: [SessionKey: URLSession] = [:]

    func session(for key: SessionKey) -> URLSession { ... }
    func invalidate(projectID: UUID) { ... }
}
```

A session key may include:

- project,
- environment,
- TLS policy,
- cookie policy.

Avoid constructing a brand new URLSession for every single request unless isolation requires it.

---

## 11.2 Metrics

Implement `URLSessionTaskDelegate` metrics collection.

Expose when available:

- total duration,
- DNS lookup,
- TCP connect,
- TLS handshake,
- request start/end,
- first response byte,
- response end,
- negotiated protocol,
- reused connection if available from metrics,
- redirect count.

Apple exposes transaction timing milestones through `URLSessionTaskTransactionMetrics`, including DNS, connect, TLS, request, and response timestamps.[^48]

Timing UI example:

```text
Queue / preparation    1 ms
DNS                   12 ms
Connect               18 ms
TLS                   27 ms
Request                2 ms
TTFB                  74 ms
Download               5 ms
Total                 139 ms
Protocol             h2
```

Do not fabricate phases when Foundation does not provide enough information.

---

## 11.3 Cancellation

Every in-flight execution must expose cancellation.

```swift
final class RequestExecutionHandle {
    let id: UUID
    func cancel()
}
```

UI:

- Send → Stop while executing.
- `Esc` cancels if the workspace owns an active request.
- cancelled requests produce a distinct “Cancelled” state, not a generic network error.

---

## 11.4 Request concurrency

MVP:

- Each request can be sent independently.
- The current detail view owns one active execution at a time.
- Re-sending the same request cancels or supersedes the previous execution after user intent is clear.

Future:

- parallel collection runner,
- multiple tabs/windows.

Do not design global singleton state that would prevent concurrent requests later.

---

## 12. Response model

Canonical response:

```swift
struct RESTResponseArtifact: Sendable, Identifiable {
    let id: UUID
    let requestID: UUID
    let startedAt: Date
    let finishedAt: Date

    let originalURL: URL
    let finalURL: URL?

    let statusCode: Int?
    let headers: [(String, String)]
    let body: Data

    let mimeType: String?
    let textEncodingName: String?
    let expectedContentLength: Int64?

    let metrics: RequestMetrics?
    let redirects: [RedirectEvent]

    let error: RESTExecutionError?
}
```

---

## 13. Response body rendering

The renderer must operate on raw `Data`, not assume every response is UTF-8 text.

Renderer selection:

```text
Response Data
  ├─ JSON renderer
  ├─ Text renderer
  ├─ Image renderer (later)
  ├─ Binary/hex renderer (later)
  └─ Raw renderer
```

MVP:

### JSON

If:

- MIME type is JSON-like, or
- data parses as JSON,

show:

- pretty formatted JSON,
- copy,
- raw toggle,
- search,
- syntax coloring.

Do not mutate the original response data.

### Text

Detect charset from HTTP response when possible; fall back carefully.

Show:

- monospaced text,
- selection,
- copy,
- find.

### Binary

MVP may show:

```text
Binary response — 42.3 KB
```

with:

- Save As…
- optional raw byte preview later.

Do not try to coerce arbitrary binary data into a string.

---

## 14. Response headers

Display response headers in a native table/list.

Columns:

- Name
- Value

Features:

- copy name,
- copy value,
- copy full header,
- search/filter later.

Preserve repeated response headers where Foundation exposes them sufficiently.

---

## 15. Response cookies

Derive cookies from response headers and/or the isolated cookie store.

Show:

- name,
- value,
- domain,
- path,
- expiry,
- Secure,
- HttpOnly.

This tab is read-only in MVP.

---

## 16. Raw request/response view

Provide a diagnostic raw view.

Request raw view should show a normalized approximation:

```http
POST /v1/users?admin=false HTTP
Host: api.example.com
Authorization: Bearer ••••••••
Content-Type: application/json

{
  "name": "Ada"
}
```

Important:

- redact Keychain-backed secrets by default,
- reveal only through explicit user action,
- make clear that HTTP/2 and HTTP/3 do not literally travel over the wire as HTTP/1.1-style text.

For this reason label it **Raw / Resolved Request** rather than claiming exact packet-wire representation.

Response raw view follows the same rule.

---

## 17. Project configuration

Each project settings view should support:

### General

- Name.
- Default/base URL.
- Default environment.
- Optional project description later.

### Environments

Examples:

```text
Development
Staging
Production
```

Fields:

- environment name,
- base URL,
- key/value variables,
- secret variables.

Insomnia’s environment model demonstrates the usefulness of base values plus environment-specific overrides for URLs, tokens, and credentials.[^49]

### Default headers

Optional project-level headers:

```text
Accept: application/json
X-Client-Version: {{clientVersion}}
```

Request-level headers override project-level headers.

### Default auth

Optional.

Request modes:

```text
Inherit
None
Custom...
```

### Networking

- timeout default,
- redirect default,
- cookie default,
- TLS default.

Keep advanced settings collapsed.

---

## 18. Variable resolution

Use:

```text
{{name}}
```

Resolution precedence:

```text
1. Request-local variables (future)
2. Selected environment variables
3. Project base/default variables
4. Built-in variables (future, if implemented)
```

MVP can omit request-local variables if unnecessary.

Rules:

- Undefined variable → validation warning.
- Secret variable remains masked in UI.
- Circular references → error.
- Limit recursion depth.
- Variables resolve at send time, not when persisted.
- The saved request text always retains placeholders.
- Resolved values never overwrite the source request.
- Copying the “resolved request” warns when secrets are included.

---

## 19. Protocol extensibility architecture

REST now, GraphQL and gRPC later must be a core architectural constraint.

## 19.1 Do not equate “request” with `URLRequest`

`URLRequest` is a REST/HTTP transport object, not the app’s universal request model.

Use:

```swift
enum APIProtocolKind: String, Codable {
    case rest
    case graphql
    case grpc
}
```

### Protocol-neutral executor

```swift
protocol APIRequestExecutor: Sendable {
    var kind: APIProtocolKind { get }

    func validate(
        requestID: UUID,
        context: ExecutionContext
    ) async throws -> [RequestValidationIssue]

    func execute(
        requestID: UUID,
        context: ExecutionContext
    ) async throws -> APIExecutionResult
}
```

Type erasure/registry:

```swift
actor RequestExecutorRegistry {
    private var executors: [APIProtocolKind: any APIRequestExecutor]

    func executor(for kind: APIProtocolKind) -> any APIRequestExecutor { ... }
}
```

UI providers should also be separated:

```swift
protocol RequestEditorProvider {
    var protocolKind: APIProtocolKind { get }
    // builds protocol-specific SwiftUI editor
}

protocol ResponseRendererProvider {
    var protocolKind: APIProtocolKind { get }
}
```

If existential SwiftUI view composition becomes awkward, use an explicit protocol-kind switch in a thin composition layer. Do not contaminate domain networking code just to avoid a UI switch.

---

## 19.2 GraphQL future design

GraphQL is transport-agnostic at the language specification level, while GraphQL-over-HTTP defines common HTTP request conventions.[^50][^51]

Future `GraphQLRequestRecord` should include:

```text
endpoint
document/query
operationName
variables JSON
headers
auth
```

Potential response UI:

```text
Response
  Data
  Errors
  Extensions
  Headers
  Timing
```

Because GraphQL-over-HTTP commonly uses POST and JSON, it can reuse much of the HTTP transport layer, but **it should not be stored as a REST request with magic body content**.

Future GraphQL editor can add:

- schema introspection,
- syntax highlighting,
- operation picker,
- variables validation,
- autocomplete,
- documentation browser.

---

## 19.3 gRPC future design

gRPC requires a separate execution model because it supports:

- unary RPC,
- client streaming,
- server streaming,
- bidirectional streaming,
- protobuf schemas/services,
- HTTP/2-based transport.

Apple now explicitly documents using modern gRPC Swift with Swift concurrency and the Swift ecosystem.[^19] The current major implementation is `grpc-swift-2`.[^20]

Future `GRPCRequestRecord`:

```text
target host
TLS mode
proto source / imported descriptor
service
method
metadata
request message JSON/editor form
streaming mode
deadline
```

Do not make gRPC go through `URLSession`.

Implement it through a `GRPCRequestExecutor` using the modern gRPC Swift packages.

The shared application layer should only unify:

- project membership,
- environment variables,
- auth/secret references where applicable,
- request naming,
- execution lifecycle,
- response/event presentation shell.

---

## 20. OpenAPI future compatibility

OpenAPI should not be required for manual requests, but the REST model should map cleanly to OpenAPI concepts:

- servers → base URLs/environments,
- paths → endpoint paths,
- operations → requests,
- path parameters,
- query parameters,
- header parameters,
- cookie parameters,
- request bodies,
- security schemes.[^30]

This makes later OpenAPI import feasible without redesign.

Possible future import flow:

```text
File → Import OpenAPI…
    ↓
Parse spec
    ↓
Choose server/environment
    ↓
Generate project
    ↓
Generate requests per operation
```

Do not make generated requests immutable; users should be able to edit them after import.

---

## 21. UI component specification

## 21.1 Method picker

Native menu/picker.

Visual method emphasis can use restrained semantic tinting, but do not create a rainbow-heavy interface.

Optional method color conventions:

- GET — subtle cool tint
- POST — subtle green tint
- PUT/PATCH — subtle warm tint
- DELETE — destructive tint

Use color as secondary information only; always show text.

## 21.2 Key/value editor

Reusable component for:

- query parameters,
- path parameters,
- headers,
- environment variables,
- form bodies later.

Capabilities:

- add row,
- delete row,
- enable/disable checkbox,
- reorder where meaningful,
- keyboard navigation,
- paste multi-line key/value input later,
- context menu,
- secret-value field mode.

Implementation should use native `Table` or a well-behaved list/grid depending on editing ergonomics.

## 21.3 Code editor

Reusable `NativeCodeEditor`.

Capabilities MVP:

- monospaced system font,
- plain-text editing,
- selection,
- undo/redo,
- copy/paste,
- system find,
- scroll,
- horizontal scroll if line wrapping disabled,
- configurable line wrap,
- JSON syntax highlighting,
- JSON error location.

Architecture:

```swift
struct NativeCodeEditor: NSViewRepresentable {
    // wraps NSTextView/TextKit
}
```

Do not implement text input manually.

## 21.4 Request/response split

Use a resizable split.

Requirements:

- horizontal divider between request editor and response,
- user can drag divider,
- persist split position,
- collapse response area if needed,
- response automatically becomes visible after first successful/failed execution.

Future:

- vertical request/response split option inspired by Proxyman’s configurable layout.[^16]

## 21.5 Inspector

Use a native SwiftUI inspector if available for the target SDK.

Potential content:

- request metadata,
- request ID,
- protocol type,
- created/modified dates,
- advanced networking settings,
- history.

Keep routine editing in the main request tabs; inspector is for secondary/advanced details.

---

## 22. Search

Use `.searchable(...)` in the sidebar context.

SwiftUI search automatically integrates into macOS navigation/toolbars; sidebar placement can appear as a sticky sidebar header attached to the toolbar.[^5][^52]

Search targets:

- project name,
- request name,
- endpoint/path,
- optionally method.

Do not search request/response bodies in MVP.

Search results should filter the sidebar without destroying hierarchy context.

---

## 23. Window behavior and restoration

Mac users expect windows to resize and restore cleanly.[^14][^53]

Persist:

- window size,
- sidebar width,
- inspector visibility,
- request/response split ratio,
- selected project,
- selected request,
- expanded projects,
- selected request tab,
- selected response tab.

On relaunch:

- reopen the last workspace state,
- do not automatically resend network requests,
- previous latest response may be absent if response persistence is disabled.

WWDC26 explicitly highlights state restoration and graceful relaunch as part of a good modern Mac experience.[^12]

---

## 24. App Sandbox and entitlements

Enable App Sandbox.

Required entitlement:

```text
Outgoing Connections (Client)
com.apple.security.network.client = true
```

Apple documents this entitlement as the sandbox permission allowing outgoing connections.[^54][^55]

Do not enable:

- incoming server connections,
- iCloud,
- contacts,
- calendar,
- camera,
- microphone,
- location,
- Apple Events,

unless a future feature explicitly requires one.

File access later:

- use `NSOpenPanel` / `NSSavePanel` and security-scoped URLs if importing/exporting files.

---

## 25. Privacy and security requirements

1. No analytics by default.
2. No request data sent anywhere except the selected API endpoint.
3. No response data sent anywhere else.
4. No cloud synchronization.
5. Secrets go to Keychain.
6. Secret values are masked by default.
7. Logs must redact:
   - Authorization,
   - Cookie,
   - Set-Cookie,
   - API key headers,
   - secret variables.
8. Crash/error logs stored locally must not include full request/response bodies by default.
9. “Copy as resolved request” must warn or redact secrets.
10. `NSAllowsArbitraryLoads` is a distribution/security decision and must not be added casually.
11. Self-signed certificate acceptance is opt-in and host-scoped.
12. Do not disable TLS validation globally as a normal default.
13. Do not reuse the system credential store unintentionally.

---

## 26. Error model

Define structured errors rather than displaying raw `NSError` everywhere.

```swift
enum RESTExecutionError: Error, Sendable {
    case invalidEndpoint(String)
    case unresolvedVariable(String)
    case invalidJSON(String)
    case authenticationConfiguration(String)
    case transport(TransportError)
    case tls(TLSError)
    case timeout
    case cancelled
    case responseTooLarge
    case unsupportedResponseEncoding
}
```

Error UI examples:

```text
Couldn’t send request
The URL contains an unresolved variable: {{host}}
```

```text
TLS verification failed
The certificate for dev.example.local is not trusted.
```

Include technical details behind a disclosure section:

- `URLError.Code`,
- host,
- underlying error,
- recovery suggestion.

Avoid modal alerts for ordinary request failures. Show failures in the response area.

---

## 27. Large response handling

Do not assume every API response is small.

Initial safeguards:

- stream or collect through URLSession normally,
- define a configurable in-memory response limit,
- default e.g. 50 MB,
- warn before rendering very large text,
- avoid syntax-highlighting the entire massive response synchronously on the main actor,
- perform JSON parsing/formatting off-main-thread,
- virtualize long displays where practical.

Future:

- stream to a temporary file,
- lazy viewer,
- Save As.

---

## 28. Concurrency design

Rules:

- UI models: `@MainActor`.
- Network execution: async Foundation APIs.
- persistence-heavy/background work: appropriate actors/model contexts.
- session manager: actor.
- secret store: actor if it simplifies serialized Keychain operations.
- JSON formatting/parsing for large bodies: detached/background work where safe.

Example:

```swift
@MainActor
@Observable
final class RequestWorkspaceModel {
    var executionState: ExecutionState = .idle
    var response: RESTResponseArtifact?

    private let coordinator: RequestExecutionCoordinator
}
```

Do not hide detached tasks inside views.

---

## 29. Suggested module/folder structure

```text
App/
  APIClientApp.swift
  AppCommands.swift
  AppEnvironment.swift

DesignSystem/
  MethodBadge.swift
  EmptyState.swift
  NativeCodeEditor.swift
  KeyValueEditor.swift

Domain/
  APIProtocolKind.swift
  Project.swift
  Request.swift
  Environment.swift
  SecretReference.swift
  ExecutionModels.swift

Persistence/
  SwiftData/
    Models/
      ProjectRecord.swift
      RequestRecord.swift
      RESTRequestRecord.swift
      EnvironmentRecord.swift
      RequestParameterRecord.swift
    PersistenceController.swift
    MigrationPlan.swift
    Mappers/

Security/
  KeychainSecretStore.swift
  SecretRedactor.swift

Networking/
  HTTP/
    RESTSessionManager.swift
    RESTURLSessionDelegate.swift
    RequestMetricsCollector.swift
    RedirectHandler.swift
  Common/
    TransportError.swift

Protocols/
  REST/
    RESTRequestExecutor.swift
    RESTRequestBuilder.swift
    RESTRequestValidator.swift
    RESTBodyEncoder.swift
    RESTAuth/
      RequestAuthenticationStrategy.swift
      BasicAuthStrategy.swift
      BearerAuthStrategy.swift
      APIKeyAuthStrategy.swift
    Models/
  GraphQL/
    README-future.md
  GRPC/
    README-future.md

Features/
  Projects/
    ProjectSidebarView.swift
    ProjectEditorView.swift
  Requests/
    RequestWorkspaceView.swift
    RequestHeaderView.swift
    RequestTabsView.swift
    ParamsEditorView.swift
    HeadersEditorView.swift
    AuthEditorView.swift
    BodyEditorView.swift
    RequestSettingsView.swift
  Responses/
    ResponseContainerView.swift
    ResponseBodyView.swift
    ResponseHeadersView.swift
    ResponseCookiesView.swift
    ResponseTimingView.swift
    RawResponseView.swift
  Environments/
    EnvironmentEditorView.swift

Tests/
  DomainTests/
  RESTRequestBuilderTests/
  RESTExecutorTests/
  PersistenceTests/
  SecurityTests/
  UITests/
```

---

## 30. Protocol-specific service boundaries

### `RESTRequestBuilder`

Input:

- saved REST request,
- project config,
- environment,
- resolved auth.

Output:

- `ResolvedRESTRequest`.

Must be pure/testable as far as possible.

### `RESTRequestExecutor`

Input:

- resolved request.

Responsibilities:

- create/configure `URLRequest`,
- select session,
- start task,
- collect response,
- collect metrics,
- capture redirects,
- return artifact.

### `SecretStore`

```swift
protocol SecretStore: Sendable {
    func read(_ reference: SecretReference) async throws -> Data?
    func write(_ data: Data, reference: SecretReference) async throws
    func delete(_ reference: SecretReference) async throws
}
```

### `VariableResolver`

```swift
protocol VariableResolving: Sendable {
    func resolve(
        _ input: String,
        scope: VariableScope
    ) throws -> ResolvedString
}
```

These boundaries make unit testing straightforward.

---

## 31. Native Mac interaction details

Implement:

- contextual menus in project/request sidebar,
- double-click request name to rename,
- Return to confirm rename where native,
- Delete key to request deletion with appropriate confirmation,
- drag reorder,
- native tooltips for icon-only toolbar items,
- menu-bar equivalents,
- undo for rename/move/delete where practical,
- system pasteboard,
- standard text editing commands,
- standard window full-screen behavior.

Do not:

- create custom title-bar buttons that compete with window controls,
- place critical actions at the bottom edge,
- replace system menus with hamburger menus,
- require single-window web-style navigation history.

Apple specifically advises using the Mac’s menu bar and avoiding critical bottom-edge controls.[^14][^56]

---

## 32. Accessibility requirements

- Native controls wherever possible.
- Every icon-only button has an accessibility label and tooltip.
- Request method must not be communicated by color alone.
- Error states include text.
- Full Keyboard Access must traverse controls correctly.
- Respect Reduce Transparency.
- Respect Increase Contrast.
- Respect system accent color.
- Respect text scaling/system font choices where applicable.
- Do not hard-code tiny developer-tool typography globally.
- Response status uses both number and semantic text when available.

SwiftUI automatically provides baseline accessibility for standard controls, which is another reason to avoid unnecessarily custom controls.[^57]

macOS 27 Liquid Glass adapts to accessibility settings such as reduced transparency and increased contrast, so standard system components should be preferred.[^13]

---

## 33. Performance requirements

Targets for ordinary projects:

- Cold launch to usable window: aim < 1 second on modern Apple Silicon where realistic.
- Selecting request: visually immediate.
- Editing fields: no debounce-induced lag.
- Sending request: UI remains responsive.
- Large response formatting: never block main actor for noticeable periods.
- Sidebar with 1,000 requests: remain usable through efficient SwiftData fetch/filter behavior.
- No background polling.
- No idle timers unless required.

Use Instruments if performance regressions appear.

---

## 34. Testing strategy

## 34.1 Unit tests

### Variable resolver

Test:

- normal substitution,
- multiple variables,
- undefined variable,
- secret variable,
- escaped braces if supported,
- recursive references,
- circular references.

### URL builder

Test:

- absolute URL,
- relative path + base URL,
- trailing/leading slash combinations,
- path parameter encoding,
- repeated query names,
- empty query value,
- Unicode,
- reserved URL characters.

### Header resolution

Test:

- project headers,
- request overrides,
- disabled headers,
- generated Content-Type,
- auth-generated Authorization,
- duplicate header handling.

### Body encoder

Test:

- no body,
- valid JSON,
- invalid JSON,
- Unicode text,
- custom Content-Type.

### Auth

Test:

- Basic,
- Bearer,
- API key header,
- API key query,
- secret missing.

### Error redaction

Test that secrets never appear in diagnostic strings.

---

## 34.2 Networking tests

Use Foundation test doubles / `URLProtocol`-based interception where suitable.

Cover:

- 2xx,
- 3xx,
- redirect disabled,
- 4xx,
- 5xx,
- timeout,
- cancellation,
- malformed response,
- JSON,
- text,
- binary,
- cookies,
- authentication challenge paths,
- metrics availability gracefully absent/present.

Use a local integration server for cases URLProtocol cannot faithfully simulate.

---

## 34.3 Persistence tests

Test:

- create project,
- create request,
- relationship cascade,
- reorder,
- environment selection,
- save/relaunch,
- schema migration when model evolves.

SwiftData supports explicit migration plans when automatic migration is insufficient.[^25][^58]

---

## 34.4 UI tests

Critical flows:

1. Launch first time.
2. Create project.
3. Add environment.
4. Create GET request.
5. Add query parameter.
6. Send.
7. Inspect response.
8. Create POST request.
9. Add JSON body.
10. Restart app.
11. Confirm project/request persisted.
12. Confirm no request was automatically re-sent.

---

## 35. MVP functional requirements

The first releasable version should include all items below.

### Projects

- [ ] Create project.
- [ ] Rename project.
- [ ] Delete project.
- [ ] Reorder projects.
- [ ] Project base URL.
- [ ] Multiple environments.
- [ ] Select active environment.
- [ ] Environment variables.
- [ ] Secret variables stored in Keychain.

### Requests

- [ ] Create request.
- [ ] Rename request.
- [ ] Duplicate request.
- [ ] Delete request.
- [ ] Reorder requests within project.
- [ ] REST protocol only.
- [ ] Methods: GET, HEAD, POST, PUT, PATCH, DELETE, OPTIONS.
- [ ] Custom method.
- [ ] Relative endpoint.
- [ ] Absolute URL.
- [ ] Path parameters.
- [ ] Query parameters.
- [ ] Headers.
- [ ] Enabled/disabled key-value rows.
- [ ] Auth: None, Inherit, Bearer, Basic, API Key.
- [ ] Body: None, JSON, Text.
- [ ] JSON validation.
- [ ] JSON formatting.
- [ ] Request timeout.
- [ ] Follow redirects on/off.
- [ ] Send.
- [ ] Cancel.

### Responses

- [ ] Status code.
- [ ] Final URL.
- [ ] Duration.
- [ ] Response size.
- [ ] Negotiated HTTP protocol when available.
- [ ] JSON pretty view.
- [ ] Text view.
- [ ] Binary fallback state.
- [ ] Headers.
- [ ] Cookies.
- [ ] Timing metrics.
- [ ] Raw/resolved view.
- [ ] Copy body.
- [ ] Save body to file optional; recommended.

### macOS integration

- [ ] Native sidebar.
- [ ] Native toolbar.
- [ ] Liquid Glass from system structures.
- [ ] Sidebar search.
- [ ] Menu bar commands.
- [ ] App Sandbox.
- [ ] Outgoing network entitlement.
- [ ] Window state restoration.
- [ ] Light/dark/system appearance.
- [ ] Accessibility labels.
- [ ] Full Keyboard Access works for ordinary controls.
- [ ] Command architecture ready for shortcuts.

### Local-only guarantees

- [ ] No sign-in.
- [ ] No cloud storage.
- [ ] No analytics.
- [ ] No telemetry.
- [ ] No CloudKit.
- [ ] Secrets stored in Keychain.
- [ ] URLSession does not unintentionally use shared persistent credentials/cache.

---

## 36. V1.1 backlog

High-value follow-up features:

1. Request history.
2. `application/x-www-form-urlencoded`.
3. `multipart/form-data`.
4. Binary/file bodies.
5. Per-project cookie jar editor.
6. Client certificates / mTLS.
7. Self-signed certificate opt-in.
8. Proxy settings.
9. Import/export project as local JSON bundle.
10. Import `curl`.
11. Copy request as `curl`.
12. More response renderers.
13. Vertical/horizontal response layout.
14. Tabs for multiple open requests.
15. OpenAPI import.
16. Request-level variables.
17. Project folders.
18. Request documentation/notes.

---

## 37. GraphQL phase

When REST V1 is stable:

- Add `APIProtocolKind.graphql`.
- Add GraphQL-specific persistence.
- Reuse project/environment/keychain systems.
- Reuse HTTP transport where appropriate.
- Add GraphQL document editor.
- Add variables JSON editor.
- Add operation name.
- Add `application/graphql-response+json` handling.
- Add response Data / Errors separation.
- Add schema introspection later.
- Add autocomplete later.

GraphQL-over-HTTP requires POST support and defines `query`, optional `operationName`, `variables`, and `extensions` as request parameters; JSON is a required serialization format in the draft transport standard.[^51]

---

## 38. gRPC phase

After GraphQL or independently:

- Add `.proto` import.
- Add service/method browser.
- Add metadata editor.
- Add protobuf message editor.
- Implement unary RPC first.
- Add server streaming.
- Add client streaming.
- Add bidirectional streaming.
- Add deadline/cancel.
- Add TLS.
- Use `grpc-swift-2` ecosystem.
- Keep stream events in a response timeline rather than forcing them into a single HTTP-style response body.

Apple’s WWDC26 guidance presents gRPC Swift as a modern Swift-concurrency-based stack and covers unary plus bidirectional streaming use cases.[^19]

---

## 39. Implementation order for an agent

### Phase 0 — scaffold

1. Create native macOS SwiftUI app.
2. Set macOS 27 deployment target.
3. Enable App Sandbox.
4. Enable outgoing client network entitlement.
5. Add local SwiftData container.
6. Add `NavigationSplitView`.
7. Add menu command structure.
8. Add protocol-neutral domain types.

### Phase 1 — persistence and sidebar

1. `ProjectRecord`.
2. `RequestRecord`.
3. `RESTRequestRecord`.
4. `EnvironmentRecord`.
5. CRUD.
6. selection.
7. search.
8. reorder.
9. restoration.

### Phase 2 — request editor

1. method picker,
2. endpoint field,
3. Params,
4. Headers,
5. Body,
6. JSON validation/format,
7. project environments,
8. variable resolution.

### Phase 3 — security/auth

1. Keychain store,
2. secret variables,
3. Bearer,
4. Basic,
5. API key,
6. redaction tests.

### Phase 4 — networking

1. request builder,
2. ephemeral URLSession configuration,
3. executor,
4. cancel,
5. redirects,
6. timeout,
7. delegate metrics.

### Phase 5 — response viewer

1. summary,
2. body renderer,
3. headers,
4. cookies,
5. timings,
6. raw view,
7. errors.

### Phase 6 — refinement

1. AppKit/TextKit code editor,
2. Liquid Glass audit,
3. accessibility audit,
4. Full Keyboard Access,
5. window restoration,
6. performance,
7. UI tests.

### Phase 7 — release hardening

1. ATS/distribution decision,
2. direct notarized build vs Mac App Store build,
3. privacy review,
4. secret/log review,
5. large response limits,
6. migration plan,
7. crash recovery.

---

## 40. Acceptance scenarios

### Scenario A — local GET

Given:

```text
Project: Worker API
Development base URL: http://localhost:8787
Request endpoint: /api/books
Method: GET
Query: limit=20
```

When Send is pressed:

Expected resolved URL:

```text
http://localhost:8787/api/books?limit=20
```

Expected UI:

- request remains editable,
- Stop appears while running,
- response status and body appear below,
- timing is available,
- project/request persist after restart.

### Scenario B — bearer secret

Given:

```text
TOKEN = secret environment variable
Authorization mode = Bearer
Token = {{TOKEN}}
```

Expected:

- token stored in Keychain,
- persisted request contains secret reference/placeholder only,
- Authorization header is applied at send time,
- token is masked in request preview,
- token does not appear in logs.

### Scenario C — POST JSON

Given:

```json
{
  "title": "Dune"
}
```

Expected:

- JSON validates before send,
- `Content-Type: application/json` is generated unless overridden,
- UTF-8 body is sent,
- response JSON is formatted without altering raw response data.

### Scenario D — environment switch

Development:

```text
http://localhost:8787
```

Production:

```text
https://api.example.com
```

Request:

```text
/books
```

Switching environment must change the resolved request target without modifying the saved endpoint.

### Scenario E — failed request

DNS failure, timeout, or TLS failure:

- no modal alert required,
- response panel displays structured error,
- technical details are expandable,
- request remains intact,
- Send can be retried.

### Scenario F — cancel

Start slow request → press Esc/Stop.

Expected:

- URLSession task cancelled,
- state becomes Cancelled,
- controls return to idle,
- no generic “network failure” label.

---

## 41. Design constraints for the implementation agent

The implementation agent must follow these rules:

1. **Do not build a custom design system when a native SwiftUI/AppKit control exists.**
2. **Do not apply glass effects to ordinary content panels just for decoration.**
3. **Do not introduce a web view for core app UI.**
4. **Do not add a backend.**
5. **Do not add authentication/account infrastructure for the app itself.**
6. **Do not add CloudKit.**
7. **Do not store secrets in SwiftData/UserDefaults/plain files.**
8. **Do not use the shared URLSession as the main REST transport.**
9. **Do not use a shared persistent credential store unintentionally.**
10. **Do not make REST fields part of the protocol-neutral request root.**
11. **Do not implement GraphQL as “just a POST body mode.”**
12. **Do not implement gRPC through URLSession.**
13. **Do not block the main actor with JSON formatting or large response parsing.**
14. **Do not invent custom keyboard navigation that fights macOS focus behavior.**
15. **Do not override standard macOS shortcuts without a strong reason.**
16. **Do not put unique actions only in the toolbar; expose commands in menus too.**
17. **Do not persist unlimited response bodies/history.**
18. **Do not disable TLS verification globally by default.**
19. **Do not add `NSAllowsArbitraryLoads` without explicitly choosing the distribution/security mode described in this spec.**
20. **Do not auto-send a request on app launch.**

---

## 42. Architectural recommendation summary

The recommended implementation is:

```text
SwiftUI macOS app
│
├── Native macOS shell
│   ├── NavigationSplitView
│   ├── Sidebar
│   ├── Toolbar
│   ├── Inspector
│   ├── Menus / Commands
│   └── Liquid Glass through system components
│
├── Local data
│   ├── SwiftData
│   └── Keychain secrets
│
├── Protocol-neutral request domain
│   ├── REST
│   ├── GraphQL (future)
│   └── gRPC (future)
│
├── REST
│   ├── Request resolver
│   ├── URLRequest builder
│   ├── Auth strategies
│   ├── URLSession ephemeral transport
│   ├── Metrics / redirects / cancellation
│   └── Response renderers
│
└── Native developer editing
    └── NSTextView + TextKit for code-like fields
```

This architecture keeps the first release small enough to build well while preserving clean extension points for the two explicitly planned future protocols.

---

# Sources

[^1]: Apple Developer. [Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/liquid-glass). Current Apple technology overview; accessed September 2026.
[^2]: Apple Developer, WWDC25. [Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/).
[^3]: Apple Developer. [NavigationSplitView](https://developer.apple.com/documentation/swiftui/navigationsplitview).
[^4]: Apple Human Interface Guidelines. [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars).
[^5]: Apple Developer. [Search](https://developer.apple.com/documentation/swiftui/search).
[^6]: Apple Developer, WWDC26. [Code-along: Add persistence with SwiftData](https://developer.apple.com/videos/play/wwdc2026/275/).
[^7]: Apple Developer. [NSTextView](https://developer.apple.com/documentation/appkit/nstextview).
[^8]: Apple Developer. [TextKit](https://developer.apple.com/documentation/appkit/textkit).
[^9]: Apple Developer, WWDC26. [Elevate your app’s text experience with TextKit](https://developer.apple.com/videos/play/wwdc2026/370/).
[^10]: Apple Developer, WWDC26 SwiftUI Group Lab. [SwiftUI Group Lab](https://developer.apple.com/videos/play/wwdc2026/8120/).
[^11]: Apple Developer. [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views).
[^12]: Apple Developer, WWDC26. [Modernize your AppKit app](https://developer.apple.com/videos/play/wwdc2026/289/).
[^13]: Apple Developer, WWDC26. [Platforms State of the Union](https://developer.apple.com/videos/play/wwdc2026/102/).
[^14]: Apple Human Interface Guidelines. [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/).
[^15]: Proxyman. [Proxyman — Native macOS HTTP debugging app](https://proxyman.com/).
[^16]: Proxyman Documentation. [Request / Response Previewer](https://docs.proxyman.com/basic-features/request-response-viewer).
[^17]: Panic. [Nova](https://nova.app/).
[^18]: TablePlus Documentation. [Left sidebar](https://docs.tableplus.com/gui-tools/the-interface/left-sidebar).
[^19]: Apple Developer, WWDC26. [Build real-time apps and services with gRPC and Swift](https://developer.apple.com/videos/play/wwdc2026/265/).
[^20]: gRPC. [grpc-swift-2](https://github.com/grpc/grpc-swift-2).
[^21]: Apple Human Interface Guidelines. [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars).
[^22]: Apple Human Interface Guidelines. [Toolbars — macOS guidance](https://developer.apple.com/design/human-interface-guidelines/toolbars).
[^23]: Apple Human Interface Guidelines. [Keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards).
[^24]: Apple Developer. [Building and customizing the menu bar with SwiftUI](https://developer.apple.com/documentation/swiftui/building-and-customizing-the-menu-bar-with-swiftui).
[^25]: Apple Developer. [ModelContainer](https://developer.apple.com/documentation/swiftdata/modelcontainer).
[^26]: Apple Developer, WWDC26. [What’s new in SwiftData](https://developer.apple.com/videos/play/wwdc2026/274/).
[^27]: Apple Developer. [Keychain services](https://developer.apple.com/documentation/security/keychain-services).
[^28]: Apple Developer. [Using the keychain to manage user secrets](https://developer.apple.com/documentation/security/using-the-keychain-to-manage-user-secrets).
[^29]: IETF / RFC Editor. [RFC 9110: HTTP Semantics](https://www.rfc-editor.org/rfc/rfc9110.html), June 2022.
[^30]: OpenAPI Initiative / Swagger. [OpenAPI Specification 3.1](https://swagger.io/specification/v3.1/).
[^31]: Postman Docs. [Send parameters and body data with API requests](https://learning.postman.com/docs/use/send-requests/create-requests/parameters).
[^32]: Kong. [Requests in Insomnia](https://developer.konghq.com/insomnia/requests/).
[^33]: Postman Docs. [Configure headers for API requests](https://learning.postman.com/docs/use/send-requests/create-requests/headers).
[^34]: Kong. [Request authentication reference — Insomnia](https://developer.konghq.com/insomnia/request-authentication/).
[^35]: Apple Developer. [URLSessionConfiguration.ephemeral](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/ephemeral).
[^36]: Apple Developer. [URLSessionConfiguration.httpCookieStorage](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/httpcookiestorage).
[^37]: Apple Developer. [Performing manual server trust authentication](https://developer.apple.com/documentation/foundation/performing-manual-server-trust-authentication).
[^38]: Apple Developer. [NSAppTransportSecurity](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity).
[^39]: Apple Developer. [NSAllowsLocalNetworking](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking).
[^40]: Apple Developer. [Preventing Insecure Network Connections](https://developer.apple.com/documentation/security/preventing-insecure-network-connections).
[^41]: Apple Developer. [NSExceptionAllowsInsecureHTTPLoads](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsexceptionallowsinsecurehttploads).
[^42]: Apple Developer. [Preventing Insecure Network Connections — Prefer High-Level Frameworks](https://developer.apple.com/documentation/security/preventing-insecure-network-connections).
[^43]: Kong. [Insomnia proxy and allowlist](https://developer.konghq.com/insomnia/allowlist/).
[^44]: IETF / RFC Editor. [RFC 9112: HTTP/1.1](https://www.rfc-editor.org/rfc/rfc9112.html), June 2022.
[^45]: IETF / RFC Editor. [RFC 9113: HTTP/2](https://www.rfc-editor.org/info/rfc9113/), June 2022.
[^46]: IETF / RFC Editor. [RFC 9114: HTTP/3](https://www.rfc-editor.org/rfc/rfc9114.html), June 2022.
[^47]: Apple Developer. [URLSessionConfiguration](https://developer.apple.com/documentation/foundation/urlsessionconfiguration).
[^48]: Apple Developer. [URLSessionTaskTransactionMetrics.fetchStartDate and related timing metrics](https://developer.apple.com/documentation/foundation/urlsessiontasktransactionmetrics/fetchstartdate).
[^49]: Kong. [Environments — Insomnia](https://developer.konghq.com/insomnia/environments/).
[^50]: GraphQL Foundation. [GraphQL Specification — September 2025](https://spec.graphql.org/September2025/).
[^51]: GraphQL contributors. [GraphQL over HTTP draft specification](https://graphql.github.io/graphql-over-http/draft/).
[^52]: Apple Developer. [SearchFieldPlacement.sidebar](https://developer.apple.com/documentation/swiftui/searchfieldplacement/sidebar).
[^53]: Apple Human Interface Guidelines. [Windows](https://developer.apple.com/design/human-interface-guidelines/windows).
[^54]: Apple Developer. [com.apple.security.network.client](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.client).
[^55]: Apple Developer. [Configuring the macOS App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox).
[^56]: Apple Human Interface Guidelines. [Layout](https://developer.apple.com/design/human-interface-guidelines/layout).
[^57]: Apple Developer. [Accessibility modifiers — SwiftUI](https://developer.apple.com/documentation/swiftui/view-accessibility).
[^58]: Apple Developer, WWDC25. [SwiftData: Dive into inheritance and schema migration](https://developer.apple.com/videos/play/wwdc2025/291/).
