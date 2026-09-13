# GraphQL + gRPC Extension Agent Specification

This specification defines how to extend the existing native macOS API client with first-class **GraphQL** and **gRPC** support, including local and remote API-definition sources, schema-aware validation, and request autocompletion.

It is written as an implementation contract for coding agents. The agent must also follow the repository-root `AGENTS.md` and the existing native macOS API-client specification. Where this document is more specific about GraphQL, gRPC, protobuf, or API-definition ingestion, this document takes precedence.

---

# 1. Mission

Add two new protocol families to the existing macOS-only API client:

1. **GraphQL**
   - Queries and mutations over HTTP.
   - Runtime GraphQL schemas from introspection or schema files.
   - Schema-aware syntax validation and autocomplete.
   - Variables, headers, authentication, and response inspection.
   - Architecture ready for subscriptions later.

2. **gRPC**
   - Unary RPC.
   - Server-streaming RPC.
   - Client-streaming RPC.
   - Bidirectional-streaming RPC.
   - Dynamic protobuf request/response handling at runtime.
   - Runtime service definitions from server reflection, `.proto` sources, directories, or descriptor sets.
   - Schema-aware JSON request editing and autocomplete.

The app remains:

- native macOS;
- Swift/SwiftUI first;
- local-only;
- account-free;
- cloud-independent;
- sandboxed;
- privacy-preserving;
- keyboard-friendly;
- compatible with the existing project/environment/secret systems.

The implementation must **not** require users to generate Swift code for their APIs.

---

# 2. Core Architectural Decision

Treat API definitions as **runtime metadata**, not source code.

Do not generate and compile Swift source whenever the user imports a GraphQL schema or protobuf definition.

A generic API client must be able to load arbitrary APIs after the app has already been built. GraphQL is naturally introspection/schema-driven, and gRPC server reflection is explicitly designed to let tooling construct requests at runtime without precompiled stubs.[^1][^2]

Use this conceptual model:

```text
Project
├── Environment(s)
├── API Definition Sources
│   ├── GraphQL schema source(s)
│   └── Protobuf/gRPC definition source(s)
└── Requests
    ├── REST
    ├── GraphQL
    └── gRPC
```

All definition sources normalize into immutable local schema snapshots:

```text
External/local source
        │
        ▼
DefinitionSourceLoader
        │
        ▼
Normalized Schema Snapshot
        │
        ├── schema browser
        ├── autocomplete
        ├── validation
        ├── method/operation discovery
        └── runtime serialization information
```

A request references a definition source, not an external file directly.

---

# 3. Research-Backed Technology Choices

## 3.1 GraphQL

### Recommended

Use **GraphQLSwift/GraphQL** as the GraphQL parser/schema/validation foundation, behind an internal adapter.

As of the research date, Swift Package Index lists GraphQLSwift/GraphQL 4.2.0 as an actively maintained Swift implementation for macOS and Linux.[^3] The project is a Swift port of the canonical GraphQL implementation.[^4]

Use it for capabilities such as:

- GraphQL document parsing;
- GraphQL type/schema representation;
- validation;
- schema construction where its public API supports the required path;
- introspection utilities where available.

Do not expose GraphQLSwift types across the whole app. Wrap the package behind:

```swift
protocol GraphQLLanguageService: Sendable {
    func loadSDL(_ source: String) throws -> GraphQLSchemaSnapshot
    func loadIntrospectionJSON(_ data: Data) throws -> GraphQLSchemaSnapshot

    func parseDocument(_ source: String) throws -> GraphQLDocument
    func validate(
        document: GraphQLDocument,
        against schema: GraphQLSchemaSnapshot
    ) -> [GraphQLDiagnostic]

    func completions(
        document: String,
        cursor: String.Index,
        schema: GraphQLSchemaSnapshot
    ) -> [CompletionItem]
}
```

Exact API signatures may differ. The abstraction is required; blindly copying these signatures is not.

### Do not use Apollo iOS as the main GraphQL engine

Apollo iOS is optimized for application developers who know their schema and operations at build time. Its normal workflow generates strongly typed Swift models from schema + operations.[^5]

That is valuable for a normal client app but conflicts with a generic API-testing application that must load arbitrary schemas at runtime.

Apollo may be used as a research reference, not as the core runtime dependency.

---

## 3.2 gRPC transport

Use the current **gRPC Swift 2.x** stack.

Required packages should be evaluated from the current compatible releases when implementation starts:

- `grpc/grpc-swift-2`
- `grpc/grpc-swift-nio-transport`
- `grpc/grpc-swift-protobuf` only where useful for statically generated canonical protocol messages.

The official gRPC Swift 2 README separates the core, SwiftNIO HTTP/2 transport, and SwiftProtobuf integration into companion packages.[^6]

As of the research date, Swift Package Index lists `grpc-swift-2` 2.4.3 as the latest release, with macOS compatibility.[^7]

Do not use the legacy gRPC Swift 1.x architecture for new implementation.

Do not route gRPC through `URLSession`.

---

## 3.3 Dynamic protobuf runtime

This is the most important gRPC-specific design constraint.

Apple's `SwiftProtobuf` is designed primarily around generated Swift message types. Its own API documentation states that it does not currently expose general descriptor objects comparable to descriptor/reflection runtimes in some other languages.[^8]

Therefore, `SwiftProtobuf` alone is not sufficient for a generic gRPC explorer that needs arbitrary runtime-loaded schemas.

### Recommended abstraction

Create:

```swift
protocol DynamicProtobufRuntime: Sendable {
    func buildRegistry(
        descriptorSet: Data
    ) throws -> ProtobufRegistry

    func validateJSON(
        _ json: String,
        messageType: ProtobufTypeID,
        registry: ProtobufRegistry
    ) -> [ProtobufDiagnostic]

    func encodeProtoJSON(
        _ json: String,
        messageType: ProtobufTypeID,
        registry: ProtobufRegistry
    ) throws -> Data

    func decodeToProtoJSON(
        _ protobuf: Data,
        messageType: ProtobufTypeID,
        registry: ProtobufRegistry
    ) throws -> String
}
```

The rest of the app must depend on this protocol rather than a concrete reflection package.

### Candidate implementation: SwiftProtoReflect

`SwiftProtoReflect` is a pure-Swift runtime protobuf reflection library that supports dynamic messages, binary and JSON serialization, oneofs, type registries, well-known types, and canonical ProtoJSON behavior.[^9]

It is unusually well matched to this application.

However, it has low ecosystem adoption compared with official gRPC/SwiftProtobuf packages. Treat it as a **qualified dependency**, not an irreversible architecture decision.

Before accepting it:

1. Build a conformance fixture covering all protobuf scalar types.
2. Cover nested messages.
3. Cover maps.
4. Cover packed repeated fields.
5. Cover enums including unknown values where valid.
6. Cover oneofs.
7. Cover proto3 optional/presence.
8. Cover proto2 required/optional/default behavior if supported.
9. Cover `google.protobuf.Timestamp`.
10. Cover `Duration`.
11. Cover `Any`.
12. Cover `Struct`, `Value`, and `ListValue`.
13. Cover wrapper types.
14. Cover 64-bit integer ProtoJSON representation.
15. Cover bytes/base64.
16. Compare binary output/decoded values against `protoc`/an official protobuf runtime.
17. Run malformed-input and recursion/size-limit tests.

If the package fails the required conformance or stability gate, replace only the `DynamicProtobufRuntime` adapter.

A possible fallback is a narrow C++ `libprotobuf` bridge using `DescriptorPool` and `DynamicMessageFactory`, but that should be a fallback because it adds a native bridging and distribution burden.

### Do not hand-write a protobuf codec as the first approach

A hand-written serializer would need to correctly implement protobuf wire types, presence, oneofs, maps, packed fields, editions/proto2/proto3 behavior, unknown fields, and canonical ProtoJSON. The official ProtoJSON specification also contains special mappings for well-known types and numeric types.[^10]

Only implement a custom codec if the qualified dynamic runtime proves unsuitable and a C++ bridge is rejected.

---

# 4. API Definition Subsystem

Add a project-level concept named **API Definitions** or **Schemas**.

Prefer the UI label **API Definitions** because it covers GraphQL schemas, protobuf definitions, reflection, and future OpenAPI definitions.

Do not call the action “Upload” in the native Mac UI unless bytes are actually being uploaded to a server.

Use:

- **Add API Definition…**
- **Attach Schema…**
- **Choose Proto Directory…**
- **Fetch Schema**
- **Refresh Definition**

All data remains local unless the user explicitly configures a remote URL/server.

---

# 5. Domain Model

Use protocol-neutral metadata plus protocol-specific configuration.

Conceptual model:

```swift
enum APIDefinitionKind: String, Codable, Sendable {
    case graphql
    case protobuf
}

enum DefinitionRefreshPolicy: String, Codable, Sendable {
    case manual
    // Future:
    // case whenOpened
    // case watchedLocalSource
}

struct DefinitionSourceID: Hashable, Codable, Sendable {
    let rawValue: UUID
}

struct SchemaSnapshotID: Hashable, Codable, Sendable {
    let rawValue: UUID
}
```

SwiftData record concept:

```swift
@Model
final class APIDefinitionRecord {
    var id: UUID
    var projectID: UUID
    var name: String
    var kindRawValue: String

    var activeSnapshotID: UUID?
    var lastSuccessfulRefreshAt: Date?
    var lastAttemptAt: Date?
    var statusRawValue: String

    // Store a protocol-specific config reference,
    // not every possible protocol field here.
}
```

Do not make one enormous schema-source model with dozens of nullable GraphQL/gRPC fields.

Prefer protocol-specific records or Codable configuration blobs with stable versioning.

---

# 6. Schema Snapshots

Definition imports must be transactional.

A failed refresh must **not** destroy the last known-good schema.

Use:

```text
Source
   │
Refresh
   ▼
Candidate snapshot
   │
Parse / resolve / validate / index
   │
   ├── failure -> retain previous active snapshot
   │             show diagnostics
   │
   └── success -> atomically set as active snapshot
```

Persist lightweight metadata in SwiftData.

Store potentially large normalized artifacts as files under the app's Application Support/container directory.

Suggested layout:

```text
Application Support/
  APIDefinitions/
    <source-id>/
      snapshots/
        <fingerprint>/
          source/
          normalized/
          diagnostics.json
```

For protobuf:

```text
normalized/
  descriptor-set.pb
```

For GraphQL:

```text
normalized/
  schema.graphql
  introspection.json        // optional, when source was introspection
  schema-index.json         // optional cache
```

Do not put multi-megabyte descriptors/SDL documents directly into frequently fetched SwiftData rows.

---

# 7. Content Fingerprints

Every successful definition snapshot should have a SHA-256 fingerprint.

Fingerprint the normalized canonical input.

Use the fingerprint to:

- avoid duplicate reindexing;
- identify whether a refresh changed anything;
- associate diagnostics/completion indexes with an exact snapshot;
- make tests deterministic.

A request should reference a `DefinitionSourceID`, not permanently bind to a snapshot ID.

At edit/execute time it uses the latest successful snapshot from that source.

If a schema update removes a referenced method/type/field, mark the request as schema-stale but do not mutate the saved request automatically.

---

# 8. Local File and Directory Access on macOS

Use native file-selection UI.

Preferred:

- SwiftUI `fileImporter` where it cleanly fits;
- `NSOpenPanel` when directory selection, multiple import roots, or richer Mac-specific behavior is required.

Use read-only security-scoped access.

Apple documents security-scoped bookmarks as the mechanism for retaining access to user-selected files across launches.[^11]

For persistent sources:

1. User chooses a file/folder.
2. Resolve the security-scoped URL.
3. Read only the files required for import.
4. Store read-only security-scoped bookmark data.
5. On later refresh:
   - resolve the bookmark;
   - handle stale bookmark data;
   - call `startAccessingSecurityScopedResource()`;
   - read;
   - always call `stopAccessingSecurityScopedResource()`.

Do not require Full Disk Access.

Do not scan unrelated directories.

---

# 9. Safe Local Schema Staging

For `.proto` compilation, do not make an embedded helper depend on arbitrary user filesystem access.

Preferred flow:

```text
NSOpenPanel
   │
security-scoped read access
   ▼
SchemaSourceReader
   │
copy only selected/required .proto inputs
   ▼
temporary staging directory inside app container
   │
   ▼
protoc helper
   │
   ▼
descriptor-set.pb
```

Preserve relative paths inside each selected import root.

Reject:

- symlink loops;
- path traversal outside an approved import root;
- excessive nesting;
- excessive file count;
- excessive cumulative size.

Skip by default:

- `.git`;
- `.svn`;
- `.build`;
- `build`;
- hidden metadata files;
- non-`.proto` files when building a proto staging tree.

Make limits explicit constants with tests.

---

# 10. gRPC Definition Sources

Support these source types.

## 10.1 Server reflection

```swift
struct GRPCReflectionSource {
    var endpoint: EndpointTemplate
    var tls: GRPCTLSConfiguration
    var metadata: [EnabledKeyValue]
    var authenticationReference: SecretReference?
}
```

Reflection is the best zero-file workflow when the server supports it.

The gRPC reflection protocol exists specifically so clients/tools can discover services and construct requests without precompiled stubs.[^1][^12]

Reflection is not automatically enabled on servers, so failure must gracefully offer file-based alternatives.[^12]

Support:

- canonical `grpc.reflection.v1`;
- compatibility fallback to `v1alpha` when needed.

Do not query reflection continuously in the background.

Refresh when:

- user adds the source;
- user explicitly presses Refresh;
- an optional future refresh preference requests it.

### Reflection implementation strategy

Statically compile the canonical reflection protocol into the app at development time.

This is allowed because the reflection service itself is known and fixed.

Use the generated reflection client only to obtain arbitrary server descriptors.

Conceptual sequence:

```text
connect
  -> open ServerReflectionInfo bidirectional stream
  -> list_services
  -> for each needed service:
       file_containing_symbol(serviceFQN)
  -> receive serialized FileDescriptorProto values
  -> deduplicate by file name
  -> resolve transitive dependencies
  -> build FileDescriptorSet
  -> normalize/index
```

The canonical reflection protocol returns serialized `FileDescriptorProto` values and may avoid re-sending descriptors already sent on the same stream.[^13]

Keep the reflection conversation on a single stream.

---

## 10.2 Local `.proto` file(s)

Allow one or multiple root `.proto` files.

UI:

```text
Add API Definition
Type: Protobuf / gRPC
Source: Proto Files

Files:
  service.proto
  common.proto

Import Roots:
  ~/Developer/project/proto
  ~/Developer/shared-protos
```

The user must be able to add import roots because imports such as:

```proto
import "company/types/common.proto";
```

cannot always be resolved relative to the root file.

Postman and grpcurl expose comparable import-path concepts for multi-file schemas.[^14][^15]

---

## 10.3 Local proto directory

Allow choosing a directory.

Recursively discover `.proto` files.

Kreya and Insomnia both support directory-oriented protobuf imports because real APIs often contain large trees of related files.[^16][^17]

Treat the chosen directory as an import root by default.

Allow additional import roots.

Do not infer that every `.proto` file contains a service. Parse all files but expose only service descriptors as callable gRPC operations.

---

## 10.4 FileDescriptorSet / protoset

Support binary `google.protobuf.FileDescriptorSet` files as a first-class source.

Recommended extensions to accept:

- `.protoset`
- `.pb`
- `.binpb`

Do not trust file extension alone; attempt descriptor decoding and report a clear parse error.

`FileDescriptorSet` is the canonical protobuf descriptor container.[^18] Tools such as grpcurl use descriptor sets directly and document `protoc --descriptor_set_out --include_imports` as an efficient reusable representation.[^15]

This source bypasses `.proto` parsing.

---

## 10.5 Remote `.proto` file

Allow an HTTPS URL to a root `.proto` file.

Example:

```text
https://example.com/protos/my/api/service.proto
```

A remote proto may import other files.

Do **not** blindly crawl arbitrary directory listings.

Model remote imports explicitly:

```swift
struct RemoteProtoSource {
    var rootFiles: [URLTemplate]
    var importRoots: [RemoteImportRoot]
    var headers: [EnabledKeyValue]
    var authenticationReference: SecretReference?
}
```

Example import mapping:

```text
proto import:
  company/types/user.proto

remote import root:
  https://raw.example.com/repository/protos/

resolved URL:
  https://raw.example.com/repository/protos/company/types/user.proto
```

Default rule:

- follow imports only under configured/approved remote import roots;
- do not cross to a new origin silently;
- do not resolve `file://` or local paths from a remote source;
- cap redirect count;
- cap file count;
- cap individual and total bytes.

Remote sources use HTTPS by default.

Allow HTTP only when the project explicitly permits insecure endpoints and present an “Insecure” indication.

---

## 10.6 Remote descriptor set

Allow fetching a descriptor set from an explicit URL.

This is preferable to a `.proto` graph when an API owner can publish a complete descriptor artifact.

Apply the same authentication/header/size/redirect policy as other remote definitions.

---

# 11. `.proto` Parsing Strategy

## Recommended production default: descriptor compilation

Normalize textual `.proto` sources to a `FileDescriptorSet`.

Do not generate Swift source.

Preferred command shape:

```text
protoc
  --proto_path=<staged-root-1>
  --proto_path=<staged-root-2>
  --proto_path=<bundled-well-known-types>
  --descriptor_set_out=<temporary-output>
  --include_imports
  --include_source_info
  <root files...>
```

`--include_imports` is required so the snapshot is self-contained.

`--include_source_info` is recommended for developer tooling because descriptor source information enables richer diagnostics/documentation locations. `descriptor.proto` explicitly describes source-code information as useful to development tools.[^18]

### Embedded `protoc`

The app should be self-contained.

Do not require the user to install Homebrew, Xcode command-line tools, or `protoc`.

Bundle a compatible `protoc` helper in the application if licensing/distribution review allows it.

Apple documents embedding command-line tools in sandboxed macOS applications, and child `Process` instances inherit the app sandbox.[^19][^20]

Rules:

- invoke `Process` directly;
- pass arguments as an array;
- never invoke through `/bin/sh`;
- never interpolate a shell command string;
- use only staged schema files in the app container;
- capture stdout/stderr;
- enforce a compilation timeout;
- kill a stuck helper;
- map compiler diagnostics back to original source URLs;
- sign/embed the helper correctly for distribution;
- ensure the helper architecture matches every supported app architecture.

Do not ship `protoc-gen-swift` for runtime importing. It is unnecessary.

### Alternative native parser

A pure-Swift parser such as `SwiftProtoParser` can parse `.proto` files into SwiftProtobuf-compatible descriptors and supports directories/import resolution.[^21]

It is attractive because it removes the helper binary.

However, it is a small/new dependency and documents limitations around full type-linking of custom options.[^21]

Therefore:

- keep `.proto -> FileDescriptorSet` behind `ProtoSchemaCompiler`;
- start with the `protoc` implementation for maximum compatibility;
- optionally build and benchmark a `SwiftProtoParserSchemaCompiler`;
- switch only if the compatibility suite proves it adequate.

```swift
protocol ProtoSchemaCompiler: Sendable {
    func compile(
        source: StagedProtoSource
    ) async throws -> CompiledDescriptorSet
}
```

---

# 12. Bundled Well-Known Protobuf Types

The app must resolve common imports without asking users to configure them manually:

```text
google/protobuf/any.proto
google/protobuf/api.proto
google/protobuf/descriptor.proto
google/protobuf/duration.proto
google/protobuf/empty.proto
google/protobuf/field_mask.proto
google/protobuf/struct.proto
google/protobuf/timestamp.proto
google/protobuf/type.proto
google/protobuf/wrappers.proto
```

Bundle the exact well-known `.proto` definitions appropriate for the selected protobuf/protoc version.

Treat them as a lowest-priority built-in import root so user-provided explicit roots can be diagnosed cleanly if there are conflicts.

Later, optionally bundle commonly used Google API annotation protos as a separate opt-in/import root.

---

# 13. Protobuf Descriptor Index

Convert every successful descriptor set into an immutable index.

Conceptual types:

```swift
struct ProtobufSchemaSnapshot: Sendable {
    let id: SchemaSnapshotID
    let files: [ProtoFileDescriptor]
    let servicesByName: [String: ProtoServiceDescriptor]
    let messagesByName: [String: ProtoMessageDescriptor]
    let enumsByName: [String: ProtoEnumDescriptor]
}

struct ProtoServiceDescriptor: Sendable {
    let fullName: String
    let documentation: String?
    let methods: [ProtoMethodDescriptor]
}

struct ProtoMethodDescriptor: Sendable {
    let serviceFullName: String
    let name: String
    let inputType: ProtobufTypeID
    let outputType: ProtobufTypeID
    let clientStreaming: Bool
    let serverStreaming: Bool
}
```

Index symbols by fully qualified protobuf name.

Do not use Swift-generated type names as persistent identities.

Persistent method identity:

```text
package.Service/Method
```

Example:

```text
acme.books.v1.LibraryService/GetBook
```

---

# 14. gRPC Request Model

Add a dedicated persisted record.

Conceptual model:

```swift
struct GRPCRequestDefinition: Codable, Sendable {
    var definitionSourceID: DefinitionSourceID

    var target: String
    var serviceFullName: String
    var methodName: String

    var metadata: [EnabledKeyValue]
    var bodyJSON: String

    var deadline: DurationConfiguration?
    var tls: GRPCTLSConfiguration
    var authorityOverride: String?

    var requestCompression: GRPCCompressionPreference?
}
```

Do not store “streaming mode” as a user-selected arbitrary value.

Derive call shape from the selected method descriptor:

```swift
enum GRPCCallShape {
    case unary
    case serverStreaming
    case clientStreaming
    case bidirectionalStreaming
}
```

---

# 15. gRPC Target Configuration

At minimum support:

- host;
- port;
- TLS enabled/disabled;
- metadata;
- deadline;
- project/environment variables.

Design extension points for:

- custom root CA;
- client certificate/mTLS;
- server-name override;
- authority override;
- compression;
- maximum inbound message size;
- maximum outbound message size;
- wait-for-ready.

gRPC core concepts include deadlines as a first-class RPC lifecycle behavior.[^22]

Secrets such as auth metadata values and private keys must use the existing Keychain/secret-reference system.

---

# 16. gRPC Dynamic Execution

Do not generate per-schema Swift stubs.

Create a runtime client layer around the gRPC Swift 2 core.

The core package defines generic message serializer/deserializer protocols for converting application messages to/from bytes.[^23]

Use a tiny wrapper type such as:

```swift
struct DynamicGRPCMessage: Sendable {
    let serializedBytes: Data
}
```

Conceptually:

```text
JSON editor
   │
DynamicProtobufRuntime
   ▼
protobuf bytes
   │
GRPC dynamic serializer
   ▼
grpc-swift-2 transport
   │
protobuf response bytes
   ▼
DynamicProtobufRuntime
   │
ProtoJSON / structured dynamic message
   ▼
response UI
```

The agent must verify current gRPC Swift 2 public APIs before writing the adapter.

Do not depend on undocumented/internal APIs.

If the currently public `GRPCCore` API cannot perform a method call using a dynamically created method descriptor, stop and isolate the smallest missing adapter rather than generating entire client modules per imported schema.

---

# 17. All Four gRPC Call Shapes

The app must support all four standard gRPC call types.[^22]

## 17.1 Unary

```text
one request message -> one response message
```

UI:

- single JSON body editor;
- Send;
- response body;
- initial metadata;
- trailing metadata;
- final gRPC status;
- timing.

Implement first.

---

## 17.2 Server streaming

```text
one request message -> many response messages
```

UI:

- one request JSON editor;
- Send;
- response event list/timeline;
- live count;
- Stop/Cancel;
- selecting an event shows full message detail;
- final trailers/status shown after stream ends.

Do not concatenate messages into one JSON array while the stream is active.

Preserve per-message arrival time and order.

---

## 17.3 Client streaming

```text
many request messages -> one response message
```

UI:

```text
Outbound Messages
  1  {...}
  2  {...}
  3  {...}

[+] Add Message

or interactive mode:

[Send Message]
[Complete Sending]
[Cancel]
```

Prefer a native list + editor/detail layout over a stack of web-style cards.

Persist a reusable list of draft messages if helpful.

Runtime session state is separate from persisted request state.

---

## 17.4 Bidirectional streaming

```text
many request messages <-> many response messages
```

Both directions operate independently.

UI should provide:

- outbound message editor;
- Send Message;
- Complete Sending;
- Cancel;
- inbound event timeline;
- metadata/status panel;
- connection/stream state.

State machine example:

```swift
enum GRPCStreamState {
    case idle
    case connecting
    case active
    case clientHalfClosed
    case completed
    case cancelled
    case failed
}
```

Do not assume request/response alternation.

gRPC explicitly allows bidirectional sides to read/write independently while preserving order within each direction.[^22]

---

# 18. gRPC Metadata

Provide a native key/value table comparable to REST headers.

Each row:

- enabled;
- key;
- value;
- optional secret toggle/reference.

Support binary metadata names ending in `-bin`.

For binary metadata, offer an explicit representation selector:

- base64 text;
- raw file later.

Do not accidentally UTF-8-coerce binary metadata.

Response UI must separate:

- initial metadata;
- trailing metadata;
- final gRPC status code/message/details.

---

# 19. Protobuf Request Editor

Use **ProtoJSON** as the human-editable representation.

This is the same general approach used by gRPC tooling such as grpcurl because binary protobuf is not practical for humans.[^15]

The editor must be descriptor-aware.

Use native `NSTextView`/TextKit according to the root `AGENTS.md`.

Do not embed Monaco or CodeMirror.

### Validation

Validate:

- JSON syntax;
- field existence;
- field value type;
- enum values;
- oneof conflicts;
- repeated value shape;
- map key/value shape;
- required proto2 fields if applicable;
- well-known type shape;
- 64-bit integer representation;
- bytes/base64;
- unknown fields.

Follow canonical ProtoJSON rules.[^10]

Do not silently discard unknown fields when the runtime's normal strict behavior would reject them.

---

# 20. gRPC Autocomplete

Autocomplete is powered entirely by the active `ProtobufSchemaSnapshot`.

## Method picker

When user chooses a definition source:

1. show services;
2. search/filter by fully qualified or short service name;
3. show methods;
4. include call shape;
5. include input → output type;
6. include source documentation when available.

Example:

```text
LibraryService
  GetBook
  SearchBooks          server streaming
  UploadBooks          client streaming
  SyncBooks            bidirectional
```

## Message editor completion

At a JSON object position, suggest fields from the current protobuf message descriptor.

Completion item should contain:

- JSON field name;
- proto field name when different;
- type;
- repeated/map marker;
- required/optional/presence information;
- oneof group;
- documentation;
- deprecation status;
- insertion text.

Examples:

```text
bookId        string
includeCover  bool
format        BookFormat enum
author        Author message
tags          repeated string
metadata      map<string, string>
```

For enums, suggest legal enum names.

For nested messages, allow inserting:

```json
"author": {

}
```

For repeated fields:

```json
"tags": [

]
```

Do not eagerly generate every nested field because recursive message graphs can be infinite.

Provide **Insert Example Body** / **Generate Request Template** as a separate command.

It should be depth-limited.

---

# 21. GraphQL Definition Sources

Support these source types.

## 21.1 Endpoint introspection

Configuration:

```swift
struct GraphQLIntrospectionSource {
    var endpoint: URLTemplate
    var headers: [EnabledKeyValue]
    var authenticationReference: SecretReference?
}
```

GraphQL is explicitly introspective/self-describing, which is intended to support developer tooling.[^24]

Fetch the current schema via an introspection query.

Reuse:

- project environment variables;
- common headers;
- authentication;
- Keychain secrets.

Allow source-level overrides.

If introspection is disabled by the server, show:

```text
Schema introspection is unavailable for this endpoint.
Attach a GraphQL SDL or introspection JSON file instead.
```

Do not treat this as a request execution failure for saved GraphQL requests.

---

## 21.2 Local SDL file

Support at least:

- `.graphql`
- `.graphqls`
- `.gql`

Parse as schema-definition language.

Because `.graphql` is also commonly used for executable operation files, detect whether the document contains type-system definitions.

If a user selects an operation-only file, explain that it is not a schema source.

---

## 21.3 Local SDL directory

Support a directory containing schema modules/extensions.

Recursively discover allowed GraphQL schema extensions.

Merge documents into one type-system document before schema construction.

Preserve each file origin so diagnostics can point to:

```text
schema/users.graphql:42:7
```

Do not recursively scan unrelated file types.

---

## 21.4 Local introspection JSON

Accept the common GraphQL introspection-result shapes:

```json
{
  "data": {
    "__schema": { ... }
  }
}
```

and, where safely identifiable:

```json
{
  "__schema": { ... }
}
```

Normalize internally.

Reject arbitrary JSON with a clear explanation.

---

## 21.5 Remote SDL URL

Fetch a schema document from an explicit URL.

Support headers/auth.

Use HTTPS by default.

Cache a successful local snapshot so the schema remains usable for autocomplete if the remote source later becomes unavailable.

This is intentionally different from tools that require the URL to remain accessible on every use.

---

## 21.6 Remote introspection JSON URL

Same behavior as remote SDL URL, but parse response as introspection JSON.

Do not execute arbitrary scripts or imports referenced by schema text.

---

# 22. GraphQL Schema Snapshot

Normalize the schema into an app-owned index.

Conceptual model:

```swift
struct GraphQLSchemaSnapshot: Sendable {
    let queryType: GraphQLNamedTypeID?
    let mutationType: GraphQLNamedTypeID?
    let subscriptionType: GraphQLNamedTypeID?

    let typesByName: [String: GraphQLTypeDescriptor]
    let directivesByName: [String: GraphQLDirectiveDescriptor]
}
```

Keep enough information for:

- autocomplete;
- validation;
- documentation;
- type navigation;
- deprecated-member display;
- variable validation;
- fragment/type-condition completion.

GraphQL descriptions are first-class schema documentation exposed through introspection.[^24]

Render description Markdown safely in a native read-only detail view.

Do not render arbitrary HTML from descriptions.

---

# 23. GraphQL Request Model

Use a dedicated GraphQL request record.

```swift
struct GraphQLRequestDefinition: Codable, Sendable {
    var definitionSourceID: DefinitionSourceID?

    var endpoint: String
    var document: String
    var operationName: String?

    var variablesJSON: String
    var extensionsJSON: String?

    var methodPreference: GraphQLHTTPMethodPreference

    var headers: [EnabledKeyValue]
    var auth: AuthenticationReference?
}
```

A schema is optional for sending GraphQL requests.

Without a schema:

- syntax highlighting still works;
- syntax parsing still works;
- request can be sent;
- schema validation/autocomplete is reduced or disabled.

This differs from gRPC, where the app needs method/message descriptors for dynamic serialization.

---

# 24. GraphQL over HTTP

Implement GraphQL HTTP transport as a GraphQL-specific executor that reuses the existing HTTP transport primitives internally.

Do **not** persist GraphQL as a REST request containing magic JSON.

The current GraphQL-over-HTTP specification is still a Stage 2 draft, so isolate the encoding rules behind:

```swift
protocol GraphQLHTTPTransport: Sendable {
    func execute(
        request: GraphQLExecutionRequest,
        context: ExecutionContext
    ) async throws -> GraphQLExecutionResponse
}
```

The draft requires POST support, defines `query`, optional `operationName`, `variables`, and `extensions`, and requires JSON support.[^25]

### POST

Default to POST.

Request body:

```json
{
  "query": "...",
  "operationName": "GetBook",
  "variables": {
    "id": "123"
  }
}
```

Set:

```text
Content-Type: application/json
Accept: application/graphql-response+json, application/json;q=0.9
```

unless the user explicitly overrides behavior.

### GET

Allow GET for query operations.

Do not use GET for mutations.

Encode:

- `query`
- `operationName`
- `variables` JSON string
- `extensions` JSON string

as URL query parameters according to the current GraphQL-over-HTTP rules.[^25]

### Response

GraphQL response semantics are not equivalent to “HTTP 2xx means no GraphQL errors.”

Parse and present:

```text
data
errors
extensions
```

independently.

Partial data and GraphQL errors can coexist.

Keep normal HTTP metadata available:

- status;
- headers;
- timing;
- response bytes.

---

# 25. GraphQL Editor

Use native TextKit.

Provide sections/tabs such as:

```text
Query | Variables | Headers | Auth
```

Do not use browser-based GraphiQL as the editor.

### Query editor features

Required:

- GraphQL syntax highlighting;
- bracket matching;
- indentation;
- comment highlighting;
- syntax diagnostics;
- schema diagnostics when schema exists;
- autocomplete;
- operation detection;
- operation picker when document contains multiple operations;
- hover/inspector documentation;
- deprecated-field indication.

Prefer a native contextual completion UI.

Use `NSTextView` completion mechanisms where they are sufficient.

If richer completion rows are necessary, use a native `NSPopover`/SwiftUI bridge anchored to the caret while preserving:

- arrow navigation;
- Enter/Tab acceptance;
- Escape dismissal;
- VoiceOver;
- focus.

---

# 26. GraphQL Autocomplete Engine

Autocomplete must be context-sensitive.

Given:

```graphql
query Book($id: ID!) {
  book(id: $id) {
    ti|
  }
}
```

the completion engine must know:

- operation root is `Query`;
- `book` return type;
- current selection-set type;
- cursor is in a field-name position;
- valid fields on that type.

Support completion contexts:

1. root fields;
2. object/interface fields;
3. arguments;
4. input-object fields;
5. enum values;
6. directives;
7. fragment spreads;
8. inline-fragment type conditions;
9. variable references;
10. named types where grammar allows them.

Completion ranking:

1. exact prefix;
2. case-insensitive prefix;
3. schema-valid context;
4. non-deprecated before deprecated;
5. fuzzy matches only after prefix matches.

Never suggest schema-invalid fields merely because the text is similar.

Completion rows should expose:

```text
title        String!
author       Author
reviews      [Review!]!
```

Secondary detail:

- description;
- arguments;
- deprecation reason;
- defining type.

---

# 27. GraphQL Validation

The September 2025 GraphQL specification states that client/development tooling should report validation errors and should not permit execution of requests known to be invalid in the given schema context.[^24]

Implement two validation tiers:

### Syntax

Always available.

Examples:

- malformed selection set;
- malformed variable definitions;
- invalid token.

### Schema validation

Available when a schema is attached.

Examples:

- unknown field;
- missing required argument;
- unknown argument;
- invalid fragment type condition;
- variable type mismatch;
- invalid enum value;
- scalar field incorrectly given a selection set.

Run validation on a debounce.

Do not perform expensive full validation for every keystroke synchronously on the main actor.

Suggested debounce:

```text
150–300 ms after last edit
```

Cancel stale validation tasks.

### Sending invalid requests

Default behavior:

- syntax-invalid request: disable Send or require explicit correction;
- schema-invalid request: disable Send by default because the active schema proves it invalid;
- no schema available: allow Send.

If the user later requests “send anyway,” make it an explicit advanced preference, not the default.

---

# 28. GraphQL Variables

Variables are JSON.

Use a separate native JSON editor.

Parse operation definitions from the GraphQL document.

When an operation is selected, derive:

```text
$id: ID!
$limit: Int = 20
$filter: BookFilter
```

Validate variable keys/types as far as GraphQL input coercion rules and custom scalar uncertainty allow.

For custom scalars:

- validate JSON representability;
- do not invent semantic rules for unknown scalars;
- show scalar description if available.

Autocomplete input-object keys and enum values where the cursor context permits.

---

# 29. GraphQL Schema Browser

Add a native inspector or sheet accessible from the attached definition.

Structure:

```text
Schema
├── Query
├── Mutation
├── Subscription
├── Types
│   ├── Objects
│   ├── Interfaces
│   ├── Unions
│   ├── Inputs
│   ├── Enums
│   └── Scalars
└── Directives
```

Selecting a type shows:

- description;
- fields;
- arguments;
- return types;
- implemented interfaces;
- possible types;
- enum values;
- input fields;
- deprecations.

Do not create a visually heavy web-style documentation dashboard.

Use native list/outline + detail/inspector patterns.

---

# 30. GraphQL Subscriptions

Do **not** include subscriptions in the first GraphQL milestone.

The GraphQL-over-HTTP draft explicitly leaves subscriptions outside its current scope.[^25]

Prepare architecture:

```swift
protocol GraphQLSubscriptionTransport
```

Future candidates:

- `graphql-transport-ws` over `URLSessionWebSocketTask`;
- an explicitly supported SSE transport.

Do not implement the deprecated `subscriptions-transport-ws` protocol as the default.

Do not make query/mutation support wait for subscriptions.

---

# 31. Definition Source Refresh

Each definition shows:

- source type;
- current status;
- last successful refresh;
- last attempted refresh;
- current fingerprint;
- warnings/errors.

States:

```swift
enum DefinitionStatus {
    case neverLoaded
    case loading
    case ready
    case staleWithError
    case unavailable
}
```

`staleWithError` means:

- refresh failed;
- previous snapshot still works.

This should be visually different from “no usable schema.”

---

# 32. Local Change Detection

MVP:

- manual Refresh.

Later:

- watch local source folder/files;
- show “Definition changed on disk”;
- let user refresh.

Do not silently regenerate the schema while the user is in the middle of editing a request unless the product explicitly adopts live refresh.

A schema change can invalidate completion context, so refresh should produce a deterministic snapshot transition.

---

# 33. Remote Refresh Semantics

Remote definitions should **not** be polled in the background by default.

This preserves the app's local/private behavior.

On explicit Refresh:

- support `ETag`;
- support `If-None-Match`;
- support `Last-Modified` / `If-Modified-Since`;
- obey normal HTTP caching semantics where useful;
- retain last successful local snapshot on network failure.

Credentials remain in Keychain.

Do not persist Authorization headers into raw schema cache files.

---

# 34. Environment Variables in Definition Sources

Definition source configuration may use the same variable syntax as requests.

Examples:

```text
https://{{apiHost}}/graphql
{{grpcHost}}:{{grpcPort}}
Authorization: Bearer {{apiToken}}
```

Resolve variables only at refresh/execution time.

Do not overwrite the saved template with resolved secret values.

Definition source fingerprints should fingerprint fetched schema content, not secret-bearing resolved headers.

---

# 35. Schema Security Model

Treat all imported schema/descriptor data as untrusted.

The protobuf project explicitly warns that runtime dynamic-message usage with untrusted descriptors requires care for denial-of-service and other security risks.[^26]

Enforce limits for:

- source file size;
- total source bytes;
- number of files;
- number of descriptors/types;
- nesting depth;
- maximum message recursion during sample generation;
- JSON document size;
- protobuf response message size;
- GraphQL SDL size;
- GraphQL type count;
- remote redirects;
- schema refresh timeout.

Do not execute code contained in schemas.

Do not:

- compile generated Swift from user schemas;
- dynamically load `.dylib` files from schema packages;
- execute schema hooks;
- run arbitrary shell commands from import metadata.

---

# 36. Remote Import Security

For remote protobuf import graphs:

- only fetch explicit root URLs;
- only follow imports through configured remote import roots;
- default to same-origin;
- require explicit user configuration for cross-origin import roots;
- prohibit `file://`;
- prohibit automatic credential forwarding to a different origin;
- strip sensitive auth when redirect crosses origin unless explicitly permitted.

This is a local developer tool, so conventional server-side SSRF is not the primary threat. Unexpected network access and credential leakage are still real threats.

---

# 37. Autocomplete Architecture Shared Across Protocols

Create a small protocol-neutral completion model:

```swift
struct CompletionItem: Sendable, Identifiable {
    enum Kind: Sendable {
        case field
        case argument
        case enumCase
        case type
        case directive
        case fragment
        case service
        case method
        case keyword
    }

    let id: String
    let label: String
    let detail: String?
    let documentation: String?
    let insertText: String
    let kind: Kind
    let deprecated: Bool
}
```

But keep context engines protocol-specific:

```text
Completion/
  Core/
    CompletionItem.swift
  GraphQL/
    GraphQLCompletionEngine.swift
  Protobuf/
    ProtoJSONCompletionEngine.swift
```

Do not attempt to build one generic grammar engine for GraphQL and ProtoJSON.

The reusable layer is UI/presentation and ranking infrastructure, not language semantics.

---

# 38. Diagnostics Architecture

Use a shared presentation model:

```swift
struct EditorDiagnostic: Sendable, Identifiable {
    enum Severity {
        case error
        case warning
        case information
    }

    let id: UUID
    let severity: Severity
    let message: String
    let range: TextRange?
    let source: String?
}
```

Protocol-specific producers:

- GraphQL parser;
- GraphQL validator;
- JSON parser;
- ProtoJSON validator;
- `.proto` compiler;
- reflection importer.

Display diagnostics natively:

- inline underline where practical;
- optional gutter indicator;
- bottom diagnostics list;
- click diagnostic → move caret/select range.

Do not show every transient parser error as a modal alert.

---

# 39. Response Model

Do not force GraphQL and gRPC into a REST response struct.

Use a protocol-neutral execution envelope:

```swift
enum APIExecutionEvent: Sendable {
    case started(Date)
    case requestMetadata(...)
    case responseMetadata(...)
    case message(APIMessage)
    case completed(APICompletion)
    case failed(APIExecutionFailure)
}
```

REST may still internally produce a single response.

GraphQL query/mutation usually produces one message.

gRPC streaming produces many message events.

This makes the response shell extensible without pretending all protocols are HTTP bodies.

---

# 40. gRPC Response UI

Suggested layout:

```text
Response
├── Messages
├── Metadata
├── Trailers
└── Details
```

For unary:

- message editor/detail fills the main response region.

For streaming:

- left/upper native event list;
- selected message detail;
- timestamp/sequence;
- live status.

Details include:

- call shape;
- elapsed duration;
- target;
- service/method;
- TLS state;
- final gRPC status.

Do not surface low-level HTTP/2 frames in the primary UI.

That may be a future advanced diagnostics feature.

---

# 41. GraphQL Response UI

Suggested sections:

```text
Response
├── Data
├── Errors
├── Extensions
├── Headers
└── Timing
```

If `data` and `errors` both exist, make both discoverable without implying the entire operation failed.

Errors should show:

- message;
- path;
- locations;
- extensions.

Preserve raw JSON view.

---

# 42. Persistence Rules

Persist:

- source configuration;
- security-scoped bookmark data;
- source display name;
- active snapshot metadata;
- request references;
- request text;
- gRPC service/method identity;
- GraphQL operation selection;
- editor preferences that are project/request-specific.

Do not persist:

- resolved secrets;
- transient network channels;
- active streaming tasks;
- in-memory descriptor registries if reconstructible;
- completion lists;
- parsed editor ASTs unless intentionally cached outside SwiftData.

---

# 43. Keychain

Use existing Keychain abstractions for:

- bearer tokens;
- Basic auth passwords;
- API keys;
- gRPC metadata secrets;
- GraphQL introspection auth;
- remote-schema URL auth;
- client-certificate passphrases;
- private keys if imported into managed secure storage.

SwiftData should store only secret references.

---

# 44. Proposed Code Organization

Adapt to the real repository; do not reorganize unrelated code just to match this tree.

```text
Domain/
  APIDefinitions/
    APIDefinitionKind.swift
    DefinitionSourceID.swift
    SchemaSnapshotID.swift
    DefinitionStatus.swift

Features/
  APIDefinitions/
    APIDefinitionsSidebarSection.swift
    AddAPIDefinitionSheet.swift
    DefinitionInspector.swift
    DefinitionDiagnosticsView.swift

  GraphQL/
    GraphQLRequestEditor.swift
    GraphQLVariablesEditor.swift
    GraphQLResponseView.swift
    GraphQLSchemaBrowser.swift

  GRPC/
    GRPCRequestEditor.swift
    GRPCMethodPicker.swift
    GRPCMetadataEditor.swift
    GRPCStreamingSessionView.swift
    GRPCResponseView.swift

Schema/
  Core/
    DefinitionRefreshCoordinator.swift
    SchemaArtifactStore.swift
    SecurityScopedBookmarkStore.swift

  GraphQL/
    GraphQLDefinitionLoader.swift
    GraphQLIntrospectionLoader.swift
    GraphQLSDLLoader.swift
    GraphQLLanguageService.swift
    GraphQLSchemaIndex.swift
    GraphQLCompletionEngine.swift

  Protobuf/
    ProtoSchemaCompiler.swift
    ProtocSchemaCompiler.swift
    ProtobufDescriptorIndex.swift
    DynamicProtobufRuntime.swift
    ProtoJSONCompletionEngine.swift
    ProtoImportResolver.swift

Networking/
  GraphQL/
    GraphQLRequestExecutor.swift
    GraphQLHTTPTransport.swift

  GRPC/
    GRPCRequestExecutor.swift
    GRPCChannelPool.swift
    GRPCDynamicInvoker.swift
    GRPCReflectionClient.swift
    GRPCStreamSession.swift
```

---

# 45. Dependency Boundaries

External packages must sit behind adapters.

```text
UI
 ↓
App domain
 ↓
internal protocols
 ↓
adapters
 ↓
GraphQLSwift / grpc-swift-2 / SwiftProtoReflect / SwiftProtobuf
```

No SwiftUI feature view should import:

- `GRPCCore`;
- `NIOCore`;
- `SwiftProtoReflect`;
- GraphQLSwift internals;

unless a narrowly scoped UI type genuinely needs a public semantic type and the dependency has been intentionally approved.

Prefer app-owned view models/domain structs.

---

# 46. Channel Pooling

gRPC should not create a new HTTP/2 connection for every request.

Create a channel pool keyed by transport-relevant configuration:

```text
host
port
TLS config identity
authority
proxy-related config if added later
```

Do not include per-call metadata such as Authorization in channel identity unless the transport library requires it.

Evict unused channels.

On project deletion/logout-equivalent data clearing, close associated channels.

---

# 47. Cancellation

Every protocol execution must support cancellation.

GraphQL:

- cancel underlying `URLSessionTask`.

gRPC unary/server streaming:

- cancel active RPC.

gRPC client/bidirectional streaming:

- stop outbound writer;
- cancel active call;
- stop incoming sequence;
- transition state exactly once.

Definition refresh:

- cancel remote fetch;
- terminate `protoc` helper if active;
- discard incomplete candidate snapshot.

Use structured Swift concurrency.

---

# 48. Native macOS UX

Continue to obey the root `AGENTS.md`.

Specific guidance:

### Project sidebar

Requests remain the primary sidebar objects.

API Definitions should appear as:

- a collapsible project section; or
- a project inspector/settings destination.

Do not let schemas dominate everyday request navigation.

### Definition management

Use a normal Mac sheet for Add API Definition.

Example:

```text
Add API Definition

Protocol:  [ GraphQL ▼ ]
Source:    [ Endpoint Introspection ▼ ]

Endpoint:  https://{{host}}/graphql

Authentication: [ Project Default ▼ ]

                         [Cancel] [Add]
```

gRPC:

```text
Add API Definition

Protocol:  [ gRPC / Protobuf ▼ ]
Source:    [ Local Proto Directory ▼ ]

Directory: ~/Developer/books-api/proto

Import Roots:
  ~/Developer/books-api/proto
  + Add Import Root

                         [Cancel] [Add]
```

### Schema browser

Prefer native split/list/outline navigation.

### Editors

Use TextKit-based native text editors.

### Completion

Keyboard-first:

- `Control-Space` or standard text-completion invocation;
- arrow keys;
- Return/Tab accepts;
- Escape closes.

Do not invent editor shortcuts that conflict with standard Mac text editing.

---

# 49. GraphQL Implementation Phases

## Phase G0 — language/service spike

Before product UI:

1. Add GraphQLSwift/GraphQL behind `GraphQLLanguageService`.
2. Load a small SDL fixture.
3. Parse a query.
4. Validate query against schema.
5. Load an introspection JSON fixture.
6. Prove type/field traversal required for completion.
7. Add tests.

Do not continue until runtime schema construction and validation are proven.

---

## Phase G1 — basic GraphQL requests

Implement:

- `.graphql` protocol kind;
- GraphQL persistence;
- POST transport;
- document editor;
- variables JSON;
- headers/auth;
- operation-name selection;
- Data / Errors / Extensions response separation;
- cancellation;
- raw response.

No schema required yet.

---

## Phase G2 — GraphQL definitions

Implement:

- local SDL;
- local SDL directory;
- local introspection JSON;
- endpoint introspection;
- remote SDL URL;
- remote introspection JSON;
- snapshot store;
- refresh;
- last-known-good behavior;
- schema browser.

---

## Phase G3 — GraphQL intelligence

Implement:

- schema-aware validation;
- autocomplete;
- operation picker;
- argument completion;
- enum completion;
- variable/input completion;
- descriptions/deprecations;
- diagnostics navigation.

---

## Phase G4 — advanced transport

Implement when requested:

- GET for queries;
- extensions UI;
- persisted-query helpers if needed;
- subscriptions;
- WebSocket/SSE transport;
- richer timing.

---

# 50. gRPC Implementation Phases

## Phase R0 — dependency qualification

Before user-facing work:

1. Add gRPC Swift 2 + transport.
2. Establish a local fixture gRPC server.
3. Prove unary generated-client call as transport sanity test.
4. Qualify `DynamicProtobufRuntime`.
5. Parse a descriptor set.
6. Encode dynamic request JSON to protobuf bytes.
7. Decode protobuf response bytes to canonical ProtoJSON.
8. Verify dynamic invocation through public gRPC Swift APIs.
9. Document any required adapter gaps.

Do not start schema UI until dynamic invocation works end-to-end.

---

## Phase R1 — descriptor set + unary

Support:

- local `.protoset`;
- descriptor index;
- service/method picker;
- unary request;
- metadata;
- deadline;
- TLS/plaintext;
- JSON request editor;
- unary response;
- status/trailers;
- validation/autocomplete.

This isolates dynamic runtime work from `.proto` compilation complexity.

---

## Phase R2 — local `.proto`

Implement:

- local files;
- local directory;
- import roots;
- staging;
- bundled well-known protos;
- `protoc -> FileDescriptorSet`;
- compiler diagnostics;
- security-scoped bookmarks;
- refresh.

---

## Phase R3 — reflection

Implement:

- canonical v1 reflection;
- v1alpha fallback;
- authenticated metadata;
- descriptor collection;
- schema refresh;
- clear reflection-disabled behavior.

---

## Phase R4 — streaming

Add in this order:

1. server streaming;
2. client streaming;
3. bidirectional streaming.

This order keeps UI/state complexity incremental.

---

## Phase R5 — remote definitions and advanced TLS

Implement:

- remote proto root;
- remote import roots;
- remote descriptor set;
- mTLS;
- custom CAs;
- advanced channel options.

---

# 51. Test Fixtures

Commit deterministic fixtures into test resources.

GraphQL:

```text
GraphQLFixtures/
  books.graphqls
  books-introspection.json
  valid-query.graphql
  invalid-query.graphql
  multi-operation.graphql
```

Protobuf:

```text
ProtoFixtures/
  simple/
  imports/
  nested/
  maps/
  oneof/
  optional/
  proto2/
  well-known-types/
  streaming/
  invalid/
```

Include at least one service containing:

```proto
service TestService {
  rpc Unary(UnaryRequest) returns (UnaryResponse);
  rpc ServerStream(StreamRequest) returns (stream StreamResponse);
  rpc ClientStream(stream StreamRequest) returns (StreamResponse);
  rpc Bidi(stream StreamRequest) returns (stream StreamResponse);
}
```

---

# 52. GraphQL Tests

Must cover:

- SDL parsing;
- SDL directory merge;
- duplicate/conflicting schema definitions;
- introspection JSON;
- authenticated introspection;
- failed introspection retaining old snapshot;
- query syntax diagnostics;
- schema validation diagnostics;
- multiple operations;
- missing operation name;
- variables parsing;
- input object autocomplete;
- enum autocomplete;
- fragment completion;
- deprecated field presentation;
- POST encoding;
- GET query encoding;
- GET mutation rejection;
- partial response (`data` + `errors`);
- non-2xx GraphQL media type;
- cancellation;
- large schema indexing off main actor.

---

# 53. Protobuf/gRPC Tests

Must cover:

### Schema

- one proto file;
- multiple files;
- directory recursion;
- import roots;
- unresolved import;
- duplicate symbol;
- malformed proto;
- descriptor set input;
- source info;
- well-known imports;
- stale bookmark;
- missing local file after relaunch;
- remote import same-origin;
- blocked cross-origin import;
- remote size limit.

### Serialization

- all scalar wire types;
- repeated;
- packed repeated;
- nested messages;
- maps;
- enums;
- oneofs;
- optional presence;
- bytes;
- signed/unsigned 64-bit values;
- Timestamp;
- Duration;
- Any;
- Struct/Value/ListValue;
- wrappers;
- unknown JSON field rejection.

### Calls

- unary success;
- unary non-OK status;
- initial metadata;
- trailers;
- deadline;
- cancellation;
- server streaming ordering;
- client streaming half-close;
- bidi independent flow;
- reflection v1;
- reflection unavailable;
- reflection auth metadata;
- schema refresh invalidating a saved method.

---

# 54. Test Oracles

Use external tools only as **development/test oracles**, not runtime dependencies.

Recommended:

- `protoc` for descriptor and wire/JSON compatibility fixtures;
- `grpcurl` for manual/reference gRPC behavior;
- a small local reference gRPC server;
- a small local GraphQL test server or deterministic HTTP fixture.

grpcurl is a useful oracle because it supports reflection, proto files, descriptor sets, JSON input, and all streaming RPC shapes.[^15]

Do not shell out to grpcurl for production request execution.

---

# 55. Performance Requirements

Do not do schema parsing/indexing on the main actor.

Target behavior:

- opening an already indexed request should be immediate;
- completion lookup should normally feel instantaneous;
- schema refresh should be cancellable;
- large proto directories should not freeze the window;
- large GraphQL schemas should not reparse on every keystroke;
- request validation should be debounced/cancellable;
- streaming responses should render incrementally without retaining unlimited formatted text objects.

For very large response streams, implement an in-memory retention cap or virtualization strategy before unbounded sessions are considered production-ready.

---

# 56. Migration

Adding GraphQL/gRPC must not break existing REST data.

Add new protocol-specific records/tables.

Do not transform REST records into a generic nullable mega-record.

Migration should preserve:

- project IDs;
- request IDs;
- environments;
- variables;
- Keychain secret references;
- REST requests exactly.

---

# 57. Explicit Non-Goals

Do not implement in the initial work unless separately requested:

- cloud schema registry accounts;
- Postman/Insomnia account import;
- Buf Schema Registry account integration;
- Apollo Studio account integration;
- GraphQL federation composition;
- GraphQL schema editing/publishing;
- protobuf schema editing/publishing;
- compiling user schemas into app-loaded Swift modules;
- server hosting;
- gRPC-Web;
- Connect protocol;
- SOAP;
- WebSocket generic client;
- GraphQL subscriptions in the first GraphQL milestone;
- gRPC health-check dashboards;
- arbitrary scripting/plugin execution.

Keep extension points where reasonable, but do not build speculative systems.

---

# 58. Prohibited Shortcuts

The coding agent must not:

- implement GraphQL as a REST request with a prebuilt JSON body and stop there;
- implement gRPC by spawning `grpcurl` for every request;
- require the user to install `protoc`;
- generate Swift code at runtime from imported `.proto`;
- compile/load user-generated Swift into the app;
- store tokens in schema config JSON;
- read arbitrary filesystem locations without user selection;
- poll remote schemas without user intent;
- make a failed refresh delete the last good snapshot;
- reimplement protobuf wire format casually;
- treat HTTP status alone as GraphQL success/failure;
- concatenate a live gRPC stream into one fake response;
- make client/bidi streaming wait for all outbound messages before displaying inbound messages;
- build GraphQL autocomplete from string regexes;
- build ProtoJSON autocomplete without descriptors;
- put parser/network/compiler work on the main actor;
- introduce a web editor to gain autocomplete;
- weaken the native macOS rules from `AGENTS.md`.

---

# 59. Architecture Review Gates

Before merging GraphQL work, verify:

- [ ] GraphQL has its own persisted request model.
- [ ] GraphQL parser/validator is behind an internal adapter.
- [ ] Requests can work without a schema.
- [ ] Definitions are project-level reusable objects.
- [ ] Last-known-good snapshot behavior is implemented.
- [ ] Introspection auth uses secret references.
- [ ] Completion is schema/context aware.
- [ ] Native TextKit editing is preserved.
- [ ] GraphQL HTTP draft details are isolated behind transport code.

Before merging gRPC work, verify:

- [ ] No per-user-schema Swift source generation occurs.
- [ ] Dynamic protobuf is behind `DynamicProtobufRuntime`.
- [ ] Descriptor set is the normalized schema representation.
- [ ] `.proto` parsing is behind `ProtoSchemaCompiler`.
- [ ] gRPC transport uses gRPC Swift 2.
- [ ] All service/method identities use protobuf FQNs.
- [ ] Unary works dynamically before streaming is added.
- [ ] Reflection becomes the same descriptor pipeline as files.
- [ ] Local directory sources use sandbox-safe access.
- [ ] ProtoJSON behavior is conformance tested.
- [ ] gRPC status and trailers are first-class response data.

---

# 60. Definition of Done

The feature set is complete when a user can perform these flows.

## GraphQL flow A — introspection

1. Create/open a project.
2. Add API Definition → GraphQL → Endpoint Introspection.
3. Enter endpoint and authentication.
4. Schema loads.
5. Create GraphQL request.
6. Attach/select schema source.
7. Type a query and receive field/argument autocomplete.
8. Invalid fields show diagnostics.
9. Add variables.
10. Send.
11. Inspect `data`, `errors`, `extensions`, HTTP headers, and timing.
12. Quit/relaunch.
13. Schema snapshot and request still work locally.

## GraphQL flow B — local schema

1. Add local `.graphqls` or schema directory.
2. Grant read-only access.
3. Schema is indexed.
4. Create queries with autocomplete.
5. Modify schema on disk.
6. Refresh definition.
7. Existing request is revalidated without its text being rewritten.

## gRPC flow A — local proto directory

1. Add API Definition → gRPC → Proto Directory.
2. Choose directory.
3. Imports resolve.
4. Services/methods appear.
5. Choose unary method.
6. Request editor autocompletes input fields/enums.
7. Send JSON-shaped ProtoJSON.
8. App serializes protobuf dynamically.
9. App receives and dynamically decodes response.
10. Status, metadata, trailers, and timing are visible.

## gRPC flow B — reflection

1. Enter a reflection-enabled target.
2. Refresh definition.
3. Services appear without local proto files.
4. Select method.
5. Execute dynamically.
6. No generated application code is produced.

## gRPC flow C — streaming

1. Select bidirectional method.
2. Start stream.
3. Send outbound message A.
4. Receive one or more inbound messages immediately.
5. Send outbound message B.
6. Half-close client side.
7. Continue receiving until server completes.
8. See final status/trailers.
9. Cancel works at any point.

## Failure flow

1. A previously valid remote schema exists.
2. Remote refresh fails.
3. App reports refresh failure.
4. Last successful snapshot remains active.
5. Existing requests still retain autocomplete/validation from that snapshot.

---

# 61. Recommended Implementation Decision Summary

Use this stack unless an implementation spike demonstrates a concrete blocker:

| Area | Decision |
|---|---|
| UI | SwiftUI + targeted AppKit/TextKit |
| Persistence | SwiftData metadata + Application Support artifact cache |
| Secrets | Keychain |
| GraphQL transport | existing Foundation/URLSession HTTP layer behind GraphQL executor |
| GraphQL language | GraphQLSwift/GraphQL behind `GraphQLLanguageService` |
| gRPC transport | grpc-swift-2 + grpc-swift-nio-transport |
| Reflection protocol | statically generated canonical reflection client |
| Runtime protobuf | `DynamicProtobufRuntime` abstraction |
| Candidate dynamic runtime | SwiftProtoReflect, only after conformance qualification |
| `.proto` normalization | bundled `protoc` → `FileDescriptorSet` |
| Alternative `.proto` parser | SwiftProtoParser behind same compiler abstraction after qualification |
| Human gRPC message format | canonical ProtoJSON |
| Local source persistence | read-only security-scoped bookmarks |
| Local compiler staging | copy permitted inputs to app-container temp directory |
| Schema refresh | explicit/manual first, last-known-good snapshots |
| Autocomplete UI | native TextKit completion/popover |
| Schema model | project-level reusable API Definition sources |

---

# 62. Agent Execution Order

An implementation agent should proceed in this exact broad order:

1. Read repository `AGENTS.md`.
2. Read existing request/domain/persistence/networking architecture.
3. Add API Definition domain abstractions without UI-heavy work.
4. Add snapshot/artifact storage.
5. Implement GraphQL language spike.
6. Implement basic GraphQL query/mutation execution.
7. Add GraphQL definition loaders.
8. Add GraphQL completion/validation.
9. Implement gRPC transport + dynamic protobuf qualification spike.
10. Implement descriptor-set unary gRPC.
11. Implement `.proto` compiler/staging.
12. Add local proto file/directory import.
13. Add gRPC reflection.
14. Add server streaming.
15. Add client streaming.
16. Add bidirectional streaming.
17. Add remote proto/descriptor sources.
18. Harden limits, security, performance, accessibility, and migration tests.
19. Update product documentation and nested `AGENTS.md` only where durable new constraints were discovered.

Do not attempt to implement every phase in one unreviewable patch.

Each phase must leave the app buildable and testable.

---

# Sources

[^1]: gRPC Authors, “GRPC Server Reflection Protocol,” gRPC repository. https://github.com/grpc/grpc/blob/master/doc/server-reflection.md
[^2]: gRPC Authors, “Reflection,” gRPC documentation. https://grpc.io/docs/guides/reflection/
[^3]: Swift Package Index, “GraphQL — GraphQLSwift/GraphQL,” current package metadata. https://swiftpackageindex.com/GraphQLSwift/GraphQL
[^4]: GraphQLSwift, “GraphQL: The Swift GraphQL implementation for macOS and Linux.” https://github.com/GraphQLSwift/GraphQL
[^5]: Apollo GraphQL, “Apollo iOS Code Generation.” https://www.apollographql.com/docs/ios/code-generation/introduction
[^6]: gRPC Authors, “gRPC Swift 2.” https://github.com/grpc/grpc-swift-2
[^7]: Swift Package Index, “grpc-swift-2.” https://swiftpackageindex.com/grpc/grpc-swift-2
[^8]: Apple, “SwiftProtobuf API — Descriptors.” https://github.com/apple/swift-protobuf/blob/main/Documentation/API.md
[^9]: truewebber, “SwiftProtoReflect.” https://github.com/truewebber/swift-protoreflect
[^10]: Protocol Buffers, “ProtoJSON Format.” https://protobuf.dev/programming-guides/json/
[^11]: Apple, “Accessing files from the macOS App Sandbox.” https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox
[^12]: gRPC Authors, “Reflection.” https://grpc.io/docs/guides/reflection/
[^13]: gRPC Authors, canonical `grpc.reflection.v1` protocol. https://github.com/grpc/grpc-proto/blob/master/grpc/reflection/v1/reflection.proto
[^14]: Postman, “Manage service definitions for gRPC requests.” https://learning.postman.com/docs/use/send-requests/protocols/grpc/using-service-definition/
[^15]: FullStory, “grpcurl.” https://github.com/fullstorydev/grpcurl
[^16]: Kreya, “gRPC importers.” https://kreya.app/docs/importers/grpc/
[^17]: Kong, “gRPC requests in Insomnia.” https://developer.konghq.com/insomnia/grpc-requests/
[^18]: Protocol Buffers, `google/protobuf/descriptor.proto`. https://github.com/protocolbuffers/protobuf/blob/main/src/google/protobuf/descriptor.proto
[^19]: Apple, “App Sandbox — Embedding a command-line tool in a sandboxed app.” https://developer.apple.com/documentation/security/app-sandbox
[^20]: Apple, `Process` documentation. https://developer.apple.com/documentation/foundation/process
[^21]: truewebber, “SwiftProtoParser.” https://github.com/truewebber/swift-protoparser
[^22]: gRPC Authors, “Core concepts, architecture and lifecycle.” https://grpc.io/docs/what-is-grpc/core-concepts/
[^23]: gRPC Swift, `MessageSerializer` and `MessageDeserializer`. https://github.com/grpc/grpc-swift-2/blob/main/Sources/GRPCCore/Coding/Coding.swift
[^24]: GraphQL Specification Project, “GraphQL Specification — September 2025.” https://spec.graphql.org/September2025/
[^25]: GraphQL over HTTP Working Group, “GraphQL over HTTP — Stage 2 Draft.” https://graphql.github.io/graphql-over-http/draft/
[^26]: Protocol Buffers, “Security — DynamicMessage on Untrusted Descriptors.” https://github.com/protocolbuffers/protobuf/security
