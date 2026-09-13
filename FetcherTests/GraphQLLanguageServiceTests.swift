import Foundation
import Testing
@testable import fetcher

struct GraphQLLanguageServiceTests {
    let service = BuiltinGraphQLLanguageService()

    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("GraphQLFixtures/\(name)")
    }

    private func fixtureString(_ name: String) throws -> String {
        try String(contentsOf: fixtureURL(name), encoding: .utf8)
    }

    @Test func loadsBooksSDLSchema() throws {
        let sdl = try fixtureString("books.graphqls")
        let schema = try service.loadSDL(sdl)

        #expect(schema.queryType?.name == "Query")
        #expect(schema.mutationType?.name == "Mutation")
        #expect(schema.typesByName["Book"]?.kind == .object)
        #expect(schema.typesByName["Book"]?.fields.contains { $0.name == "title" } == true)
        #expect(schema.rootQueryFields.contains { $0.name == "book" })
    }

    @Test func parsesValidQueryDocument() throws {
        let source = try fixtureString("valid-query.graphql")
        let document = try service.parseDocument(source)

        #expect(document.operations.count == 1)
        #expect(document.operations[0].kind == .query)
        #expect(document.operations[0].name == "GetBook")
        #expect(document.operations[0].variableDefinitions.count == 1)
        #expect(document.operations[0].variableDefinitions[0].name == "id")
        #expect(document.operations[0].variableDefinitions[0].typeName == "ID!")
    }

    @Test func parsesMultiOperationDocument() throws {
        let source = try fixtureString("multi-operation.graphql")
        let document = try service.parseDocument(source)

        #expect(document.operations.count == 2)
        #expect(document.operations[0].kind == .query)
        #expect(document.operations[0].name == "ListBooks")
        #expect(document.operations[1].kind == .mutation)
        #expect(document.operations[1].name == "CreateBook")
    }

    @Test func validatesUnknownFieldAsError() throws {
        let sdl = try fixtureString("books.graphqls")
        let schema = try service.loadSDL(sdl)
        let source = try fixtureString("invalid-query.graphql")
        let document = try service.parseDocument(source)

        let diagnostics = service.validate(document: document, against: schema)
        #expect(diagnostics.contains { $0.severity == .error && $0.message.contains("unknownField") })
    }

    @Test func syntaxDiagnosticsDetectUnmatchedBrace() {
        let diagnostics = service.syntaxDiagnostics(in: "query { book(id: 1) { id ")
        #expect(diagnostics.contains { $0.message.contains("Unmatched") })
    }

    @Test func loadsIntrospectionJSONWrappedInData() throws {
        let json = """
        {
          "data": {
            "__schema": {
              "queryType": { "name": "Query" },
              "mutationType": { "name": "Mutation" },
              "subscriptionType": null,
              "types": [
                {
                  "kind": "OBJECT",
                  "name": "Query",
                  "description": null,
                  "fields": [
                    {
                      "name": "book",
                      "description": null,
                      "args": [
                        {
                          "name": "id",
                          "description": null,
                          "type": { "kind": "NON_NULL", "name": null, "ofType": { "kind": "SCALAR", "name": "ID", "ofType": null } },
                          "defaultValue": null
                        }
                      ],
                      "type": { "kind": "OBJECT", "name": "Book", "ofType": null },
                      "isDeprecated": false,
                      "deprecationReason": null
                    }
                  ],
                  "inputFields": null,
                  "interfaces": [],
                  "enumValues": null,
                  "possibleTypes": null
                },
                {
                  "kind": "OBJECT",
                  "name": "Book",
                  "description": null,
                  "fields": [
                    {
                      "name": "title",
                      "description": null,
                      "args": [],
                      "type": { "kind": "NON_NULL", "name": null, "ofType": { "kind": "SCALAR", "name": "String", "ofType": null } },
                      "isDeprecated": false,
                      "deprecationReason": null
                    }
                  ],
                  "inputFields": null,
                  "interfaces": [],
                  "enumValues": null,
                  "possibleTypes": null
                }
              ],
              "directives": []
            }
          }
        }
        """
        let schema = try service.loadIntrospectionJSON(Data(json.utf8))
        #expect(schema.queryType?.name == "Query")
        #expect(schema.typesByName["Book"]?.fields.contains { $0.name == "title" } == true)
    }

    @Test func loadsIntrospectionJSONRootSchemaShape() throws {
        let json = """
        {
          "__schema": {
            "queryType": { "name": "Query" },
            "mutationType": null,
            "subscriptionType": null,
            "types": [
              {
                "kind": "OBJECT",
                "name": "Query",
                "description": null,
                "fields": [],
                "inputFields": null,
                "interfaces": [],
                "enumValues": null,
                "possibleTypes": null
              }
            ],
            "directives": []
          }
        }
        """
        let schema = try service.loadIntrospectionJSON(Data(json.utf8))
        #expect(schema.queryType?.name == "Query")
    }

    @Test func completionEngineRanksExactPrefixFirst() throws {
        let sdl = try fixtureString("books.graphqls")
        let schema = try service.loadSDL(sdl)
        let document = """
        query {
          b
        """
        let engine = GraphQLCompletionEngine(languageService: service)
        let items = engine.completions(document: document, cursorUTF16Offset: document.utf16.count, schema: schema, prefix: "b")
        #expect(!items.isEmpty)
        #expect(items.first?.label == "book" || items.first?.label == "books")
    }

    @Test func completionsSuggestQueryRootFieldsAfterBrace() throws {
        let sdl = try fixtureString("books.graphqls")
        let schema = try service.loadSDL(sdl)
        let document = "query { "
        let items = service.completions(document: document, cursorUTF16Offset: document.utf16.count, schema: schema)
        let labels = Set(items.map(\.label))
        #expect(labels.contains("book"))
        #expect(labels.contains("books"))
    }
}
