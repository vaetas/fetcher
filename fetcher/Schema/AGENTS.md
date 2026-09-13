# Schema / Protocol Agents

When working under GraphQL or gRPC code:

- Keep external packages behind adapters (`GraphQLLanguageService`, `DynamicProtobufRuntime`, `ProtoSchemaCompiler`).
- Do not generate Swift from user schemas at runtime.
- Persist API definition metadata in SwiftData; store large artifacts under Application Support via `SchemaArtifactStore`.
- Preserve last-known-good snapshots on refresh failure.
- GraphQL requests must work without an attached schema; gRPC requires descriptors for dynamic serialization.
- Prefer native TextKit editors and protocol-specific response models.
