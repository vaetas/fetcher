import Foundation

enum GraphQLLanguageError: Error, Sendable, Equatable {
    case parseError(String)
    case invalidIntrospection(String)
    case limitExceeded(String)
}

struct BuiltinGraphQLLanguageService: GraphQLLanguageService, Sendable {
    func loadSDL(_ source: String) throws -> GraphQLSchemaSnapshot {
        let parser = GraphQLSDLParser(source: source)
        return try parser.parse()
    }

    func loadIntrospectionJSON(_ data: Data) throws -> GraphQLSchemaSnapshot {
        try GraphQLIntrospectionParser(data: data).parse()
    }

    func parseDocument(_ source: String) throws -> GraphQLDocument {
        let parser = GraphQLDocumentParser(source: source)
        return try parser.parse()
    }

    func validate(document: GraphQLDocument, against schema: GraphQLSchemaSnapshot) -> [EditorDiagnostic] {
        GraphQLDocumentValidator(document: document, schema: schema).validate()
    }

    func completions(
        document: String,
        cursorUTF16Offset: Int,
        schema: GraphQLSchemaSnapshot
    ) -> [CompletionItem] {
        GraphQLCompletionProvider(document: document, cursorUTF16Offset: cursorUTF16Offset, schema: schema)
            .completions()
    }

    func syntaxDiagnostics(in source: String) -> [EditorDiagnostic] {
        GraphQLSyntaxChecker(source: source).diagnostics()
    }
}

// MARK: - Lexer

private enum GraphQLTokenKind: Equatable {
    case name(String)
    case intValue(String)
    case floatValue(String)
    case string(String)
    case bang
    case dollar
    case amp
    case parenOpen
    case parenClose
    case braceOpen
    case braceClose
    case bracketOpen
    case bracketClose
    case colon
    case equals
    case pipe
    case at
    case ellipsis
    case eof
}

private struct GraphQLToken: Equatable {
    let kind: GraphQLTokenKind
    let startUTF16: Int
    let endUTF16: Int
}

private struct GraphQLLexer {
    let source: String
    private var index: String.Index
    private var utf16Offset: Int

    init(source: String) {
        self.source = source
        self.index = source.startIndex
        self.utf16Offset = 0
    }

    mutating func tokenize() -> [GraphQLToken] {
        var tokens: [GraphQLToken] = []
        while true {
            skipIgnored()
            let startUTF16 = utf16Offset
            guard index < source.endIndex else {
                tokens.append(GraphQLToken(kind: .eof, startUTF16: startUTF16, endUTF16: startUTF16))
                break
            }
            let kind = nextTokenKind()
            let endUTF16 = utf16Offset
            tokens.append(GraphQLToken(kind: kind, startUTF16: startUTF16, endUTF16: endUTF16))
            if case .eof = kind { break }
        }
        return tokens
    }

    private mutating func skipIgnored() {
        while index < source.endIndex {
            let scalar = source[index]
            if scalar.isWhitespace {
                advance()
                continue
            }
            if scalar == "#" {
                while index < source.endIndex, source[index] != "\n" {
                    advance()
                }
                continue
            }
            if scalar == "," {
                advance()
                continue
            }
            break
        }
    }

    private mutating func nextTokenKind() -> GraphQLTokenKind {
        let scalar = source[index]
        switch scalar {
        case "!": advance(); return .bang
        case "$": advance(); return .dollar
        case "&": advance(); return .amp
        case "(": advance(); return .parenOpen
        case ")": advance(); return .parenClose
        case "{": advance(); return .braceOpen
        case "}": advance(); return .braceClose
        case "[": advance(); return .bracketOpen
        case "]": advance(); return .bracketClose
        case ":": advance(); return .colon
        case "=": advance(); return .equals
        case "|": advance(); return .pipe
        case "@": advance(); return .at
        case ".": return readEllipsisOrFloat()
        case "\"": return .string(readString())
        case "-": return readNumber()
        default:
            if scalar.isNumber {
                return readNumber()
            }
            if isNameStart(scalar) {
                return .name(readName())
            }
            advance()
            return .name(String(scalar))
        }
    }

    private mutating func readEllipsisOrFloat() -> GraphQLTokenKind {
        let savedIndex = index
        let savedOffset = utf16Offset
        if peekMatches("...") {
            advance(count: 3)
            return .ellipsis
        }
        index = savedIndex
        utf16Offset = savedOffset
        return readNumber()
    }

    private mutating func readNumber() -> GraphQLTokenKind {
        let start = index
        var isFloat = false
        if source[index] == "-" { advance() }
        while index < source.endIndex, source[index].isNumber {
            advance()
        }
        if index < source.endIndex, source[index] == "." {
            isFloat = true
            advance()
            while index < source.endIndex, source[index].isNumber {
                advance()
            }
        }
        let text = String(source[start..<index])
        return isFloat ? .floatValue(text) : .intValue(text)
    }

    private mutating func readString() -> String {
        advance() // opening quote
        if peekMatches("\"\"\"") {
            advance(count: 3)
            var value = ""
            while index < source.endIndex {
                if peekMatches("\"\"\"") {
                    advance(count: 3)
                    return blockStringValue(value)
                }
                value.append(source[index])
                advance()
            }
            return blockStringValue(value)
        }
        var value = ""
        while index < source.endIndex {
            if source[index] == "\\" {
                advance()
                if index < source.endIndex {
                    value.append(source[index])
                    advance()
                }
                continue
            }
            if source[index] == "\"" {
                advance()
                return value
            }
            value.append(source[index])
            advance()
        }
        return value
    }

    private mutating func readName() -> String {
        var value = ""
        while index < source.endIndex, isNameContinue(source[index]) {
            value.append(source[index])
            advance()
        }
        return value
    }

    private mutating func advance(count: Int = 1) {
        for _ in 0..<count {
            guard index < source.endIndex else { return }
            index = source.index(after: index)
            utf16Offset = source.utf16.distance(from: source.startIndex, to: index)
        }
    }

    private func peekMatches(_ text: String) -> Bool {
        var cursor = index
        for char in text {
            guard cursor < source.endIndex, source[cursor] == char else { return false }
            cursor = source.index(after: cursor)
        }
        return true
    }

    private func isNameStart(_ scalar: Character) -> Bool {
        scalar == "_" || scalar.isLetter
    }

    private func isNameContinue(_ scalar: Character) -> Bool {
        scalar == "_" || scalar.isLetter || scalar.isNumber
    }

    private func blockStringValue(_ raw: String) -> String {
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let first = lines.first else { return "" }
        var commonIndent: Int?
        for line in lines.dropFirst() {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let indent = line.prefix { $0 == " " || $0 == "\t" }.count
            commonIndent = min(commonIndent ?? indent, indent)
        }
        let indent = commonIndent ?? 0
        var result = first.trimmingCharacters(in: .whitespaces)
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                result.append("\n")
            } else if line.count >= indent {
                result.append("\n")
                result.append(String(line.dropFirst(indent)))
            } else {
                result.append("\n")
                result.append(line)
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Token cursor

private struct GraphQLTokenCursor {
    let tokens: [GraphQLToken]
    private(set) var position = 0

    var current: GraphQLToken {
        guard position < tokens.count else { return tokens.last ?? GraphQLToken(kind: .eof, startUTF16: 0, endUTF16: 0) }
        return tokens[position]
    }

    mutating func advance() {
        if position < tokens.count - 1 {
            position += 1
        }
    }

    mutating func expect(_ kind: GraphQLTokenKind) throws {
        guard current.kind == kind else {
            throw GraphQLLanguageError.parseError("Unexpected token at offset \(current.startUTF16)")
        }
        advance()
    }

    mutating func expectName(_ name: String) throws {
        guard case .name(let value) = current.kind, value == name else {
            throw GraphQLLanguageError.parseError("Expected '\(name)' at offset \(current.startUTF16)")
        }
        advance()
    }

    func match(_ kind: GraphQLTokenKind) -> Bool {
        current.kind == kind
    }

    func matchName(_ name: String) -> Bool {
        if case .name(let value) = current.kind { return value == name }
        return false
    }

    mutating func skip(kind: GraphQLTokenKind) -> Bool {
        guard match(kind) else { return false }
        advance()
        return true
    }

    mutating func parseName() throws -> String {
        guard case .name(let value) = current.kind else {
            throw GraphQLLanguageError.parseError("Expected name at offset \(current.startUTF16)")
        }
        advance()
        return value
    }

    mutating func parseDescription() -> String? {
        guard case .string(let value) = current.kind else { return nil }
        advance()
        return value
    }

    mutating func parseTypeReference() throws -> String {
        var result = ""
        if skip(kind: .bracketOpen) {
            result.append("[")
            result.append(try parseTypeReference())
            try expect(.bracketClose)
            result.append("]")
        } else {
            result.append(try parseName())
        }
        if skip(kind: .bang) {
            result.append("!")
        }
        return result
    }

    mutating func parseDefaultValue() throws -> String {
        switch current.kind {
        case .name(let value):
            advance()
            return value
        case .intValue(let value), .floatValue(let value), .string(let value):
            advance()
            return value
        case .dollar:
            advance()
            let name = try parseName()
            return "$\(name)"
        case .braceOpen:
            return try parseInputObjectDefault()
        case .bracketOpen:
            return try parseListDefault()
        default:
            throw GraphQLLanguageError.parseError("Expected default value at offset \(current.startUTF16)")
        }
    }

    private mutating func parseInputObjectDefault() throws -> String {
        try expect(.braceOpen)
        var parts: [String] = []
        while !match(.braceClose) {
            let name = try parseName()
            try expect(.colon)
            let value = try parseDefaultValue()
            parts.append("\(name): \(value)")
        }
        try expect(.braceClose)
        return "{\(parts.joined(separator: ", "))}"
    }

    private mutating func parseListDefault() throws -> String {
        try expect(.bracketOpen)
        var values: [String] = []
        while !match(.bracketClose) {
            values.append(try parseDefaultValue())
        }
        try expect(.bracketClose)
        return "[\(values.joined(separator: ", "))]"
    }

    mutating func parseInputValueDefinition() throws -> GraphQLArgumentDescriptor {
        let description = parseDescription()
        let name = try parseName()
        try expect(.colon)
        let typeName = try parseTypeReference()
        var defaultValue: String?
        if skip(kind: .equals) {
            defaultValue = try parseDefaultValue()
        }
        let directives = try parseDirectivesConstant()
        let deprecated = directives.contains { $0.name == "deprecated" }
        let deprecationReason = directives.first { $0.name == "deprecated" }?.arguments["reason"]
        return GraphQLArgumentDescriptor(
            name: name,
            typeName: typeName,
            defaultValue: defaultValue,
            description: description,
            isDeprecated: deprecated,
            deprecationReason: deprecationReason
        )
    }

    mutating func parseFieldDefinition() throws -> GraphQLFieldDescriptor {
        let description = parseDescription()
        let name = try parseName()
        var arguments: [GraphQLArgumentDescriptor] = []
        if skip(kind: .parenOpen) {
            while !match(.parenClose) {
                arguments.append(try parseInputValueDefinition())
            }
            try expect(.parenClose)
        }
        try expect(.colon)
        let typeName = try parseTypeReference()
        let directives = try parseDirectivesConstant()
        let deprecated = directives.contains { $0.name == "deprecated" }
        let deprecationReason = directives.first { $0.name == "deprecated" }?.arguments["reason"]
        return GraphQLFieldDescriptor(
            name: name,
            typeName: typeName,
            description: description,
            arguments: arguments,
            isDeprecated: deprecated,
            deprecationReason: deprecationReason
        )
    }

    struct ParsedDirective {
        let name: String
        let arguments: [String: String]
    }

    mutating func parseDirectivesConstant() throws -> [ParsedDirective] {
        var result: [ParsedDirective] = []
        while skip(kind: .at) {
            let name = try parseName()
            var args: [String: String] = [:]
            if skip(kind: .parenOpen) {
                while !match(.parenClose) {
                    let argName = try parseName()
                    try expect(.colon)
                    let value = try parseDefaultValue()
                    args[argName] = value
                }
                try expect(.parenClose)
            }
            result.append(ParsedDirective(name: name, arguments: args))
        }
        return result
    }

    mutating func parseInputFieldDefinition() throws -> GraphQLInputFieldDescriptor {
        let description = parseDescription()
        let name = try parseName()
        try expect(.colon)
        let typeName = try parseTypeReference()
        var defaultValue: String?
        if skip(kind: .equals) {
            defaultValue = try parseDefaultValue()
        }
        let directives = try parseDirectivesConstant()
        let deprecated = directives.contains { $0.name == "deprecated" }
        return GraphQLInputFieldDescriptor(
            name: name,
            typeName: typeName,
            description: description,
            defaultValue: defaultValue,
            isDeprecated: deprecated
        )
    }

    mutating func parseEnumValueDefinition() throws -> GraphQLEnumValueDescriptor {
        let description = parseDescription()
        let name = try parseName()
        let directives = try parseDirectivesConstant()
        let deprecated = directives.contains { $0.name == "deprecated" }
        let deprecationReason = directives.first { $0.name == "deprecated" }?.arguments["reason"]
        return GraphQLEnumValueDescriptor(
            name: name,
            description: description,
            isDeprecated: deprecated,
            deprecationReason: deprecationReason
        )
    }
}

// MARK: - SDL parser

private struct GraphQLSDLParser {
    let source: String

    func parse() throws -> GraphQLSchemaSnapshot {
        var lexer = GraphQLLexer(source: source)
        let tokens = lexer.tokenize()
        var cursor = GraphQLTokenCursor(tokens: tokens)

        var typesByName: [String: GraphQLTypeDescriptor] = [:]
        var directivesByName: [String: GraphQLDirectiveDescriptor] = [:]
        var queryType: GraphQLNamedTypeID?
        var mutationType: GraphQLNamedTypeID?
        var subscriptionType: GraphQLNamedTypeID?

        while !cursor.match(.eof) {
            let description = cursor.parseDescription()
            if cursor.matchName("schema") {
                try cursor.expectName("schema")
                try cursor.expect(.braceOpen)
                while !cursor.match(.braceClose) {
                    let key = try cursor.parseName()
                    try cursor.expect(.colon)
                    let value = try cursor.parseName()
                    switch key {
                    case "query": queryType = GraphQLNamedTypeID(name: value)
                    case "mutation": mutationType = GraphQLNamedTypeID(name: value)
                    case "subscription": subscriptionType = GraphQLNamedTypeID(name: value)
                    default: break
                    }
                }
                try cursor.expect(.braceClose)
                continue
            }

            if cursor.matchName("directive") {
                let directive = try parseDirectiveDefinition(&cursor)
                directivesByName[directive.name] = directive
                continue
            }

            if cursor.matchName("scalar") {
                try cursor.expectName("scalar")
                let name = try cursor.parseName()
                typesByName[name] = GraphQLTypeDescriptor(
                    name: name,
                    kind: .scalar,
                    description: description,
                    fields: [],
                    inputFields: [],
                    enumValues: [],
                    interfaces: [],
                    possibleTypes: []
                )
                continue
            }

            if cursor.matchName("type") {
                let type = try parseObjectType(&cursor, description: description, kind: .object)
                typesByName[type.name] = type
                continue
            }

            if cursor.matchName("interface") {
                let type = try parseObjectType(&cursor, description: description, kind: .interface)
                typesByName[type.name] = type
                continue
            }

            if cursor.matchName("union") {
                try cursor.expectName("union")
                let name = try cursor.parseName()
                try cursor.expect(.equals)
                var possibleTypes: [String] = []
                repeat {
                    possibleTypes.append(try cursor.parseName())
                } while cursor.skip(kind: .pipe)
                typesByName[name] = GraphQLTypeDescriptor(
                    name: name,
                    kind: .union,
                    description: description,
                    fields: [],
                    inputFields: [],
                    enumValues: [],
                    interfaces: [],
                    possibleTypes: possibleTypes
                )
                continue
            }

            if cursor.matchName("enum") {
                try cursor.expectName("enum")
                let name = try cursor.parseName()
                try cursor.expect(.braceOpen)
                var enumValues: [GraphQLEnumValueDescriptor] = []
                while !cursor.match(.braceClose) {
                    enumValues.append(try cursor.parseEnumValueDefinition())
                }
                try cursor.expect(.braceClose)
                typesByName[name] = GraphQLTypeDescriptor(
                    name: name,
                    kind: .enumType,
                    description: description,
                    fields: [],
                    inputFields: [],
                    enumValues: enumValues,
                    interfaces: [],
                    possibleTypes: []
                )
                continue
            }

            if cursor.matchName("input") {
                try cursor.expectName("input")
                let name = try cursor.parseName()
                try cursor.expect(.braceOpen)
                var inputFields: [GraphQLInputFieldDescriptor] = []
                while !cursor.match(.braceClose) {
                    inputFields.append(try cursor.parseInputFieldDefinition())
                }
                try cursor.expect(.braceClose)
                typesByName[name] = GraphQLTypeDescriptor(
                    name: name,
                    kind: .inputObject,
                    description: description,
                    fields: [],
                    inputFields: inputFields,
                    enumValues: [],
                    interfaces: [],
                    possibleTypes: []
                )
                continue
            }

            if case .name = cursor.current.kind {
                cursor.advance()
                continue
            }
            cursor.advance()
        }

        if queryType == nil, typesByName["Query"] != nil {
            queryType = GraphQLNamedTypeID(name: "Query")
        }
        if mutationType == nil, typesByName["Mutation"] != nil {
            mutationType = GraphQLNamedTypeID(name: "Mutation")
        }
        if subscriptionType == nil, typesByName["Subscription"] != nil {
            subscriptionType = GraphQLNamedTypeID(name: "Subscription")
        }

        if typesByName.count > SchemaResourceLimits.maxGraphQLTypeCount {
            throw GraphQLLanguageError.limitExceeded("Schema exceeds maximum type count.")
        }

        return GraphQLSchemaSnapshot(
            id: SchemaSnapshotID(),
            queryType: queryType,
            mutationType: mutationType,
            subscriptionType: subscriptionType,
            typesByName: typesByName,
            directivesByName: directivesByName
        )
    }

    private func parseObjectType(
        _ cursor: inout GraphQLTokenCursor,
        description: String?,
        kind: GraphQLTypeDescriptor.Kind
    ) throws -> GraphQLTypeDescriptor {
        try cursor.expectName(kind == .object ? "type" : "interface")
        let name = try cursor.parseName()
        var interfaces: [String] = []
        if cursor.matchName("implements") {
            try cursor.expectName("implements")
            repeat {
                interfaces.append(try cursor.parseName())
            } while cursor.skip(kind: .amp)
        }
        try cursor.expect(.braceOpen)
        var fields: [GraphQLFieldDescriptor] = []
        while !cursor.match(.braceClose) {
            fields.append(try cursor.parseFieldDefinition())
        }
        try cursor.expect(.braceClose)
        return GraphQLTypeDescriptor(
            name: name,
            kind: kind,
            description: description,
            fields: fields,
            inputFields: [],
            enumValues: [],
            interfaces: interfaces,
            possibleTypes: []
        )
    }

    private func parseDirectiveDefinition(_ cursor: inout GraphQLTokenCursor) throws -> GraphQLDirectiveDescriptor {
        let description = cursor.parseDescription()
        try cursor.expectName("directive")
        try cursor.expect(.at)
        let name = try cursor.parseName()
        var arguments: [GraphQLArgumentDescriptor] = []
        if cursor.skip(kind: .parenOpen) {
            while !cursor.match(.parenClose) {
                arguments.append(try cursor.parseInputValueDefinition())
            }
            try cursor.expect(.parenClose)
        }
        try cursor.expectName("on")
        var locations: [String] = []
        repeat {
            locations.append(try cursor.parseName())
        } while cursor.skip(kind: .pipe)
        return GraphQLDirectiveDescriptor(
            name: name,
            description: description,
            locations: locations,
            arguments: arguments
        )
    }
}

// MARK: - Introspection JSON

private struct GraphQLIntrospectionParser {
    let data: Data

    func parse() throws -> GraphQLSchemaSnapshot {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let root = json as? [String: Any] else {
            throw GraphQLLanguageError.invalidIntrospection("Expected JSON object.")
        }

        let schemaObject: [String: Any]
        if let dataObject = root["data"] as? [String: Any], let schema = dataObject["__schema"] as? [String: Any] {
            schemaObject = schema
        } else if let schema = root["__schema"] as? [String: Any] {
            schemaObject = schema
        } else {
            throw GraphQLLanguageError.invalidIntrospection("Missing __schema object.")
        }

        let queryType = namedTypeID(from: schemaObject["queryType"] as? [String: Any])
        let mutationType = namedTypeID(from: schemaObject["mutationType"] as? [String: Any])
        let subscriptionType = namedTypeID(from: schemaObject["subscriptionType"] as? [String: Any])

        var typesByName: [String: GraphQLTypeDescriptor] = [:]
        if let types = schemaObject["types"] as? [[String: Any]] {
            for typeJSON in types {
                guard let name = typeJSON["name"] as? String else { continue }
                let kind = mapKind(typeJSON["kind"] as? String)
                let fields = parseFields(typeJSON["fields"] as? [[String: Any]] ?? [])
                let inputFields = parseInputFields(typeJSON["inputFields"] as? [[String: Any]] ?? [])
                let enumValues = parseEnumValues(typeJSON["enumValues"] as? [[String: Any]] ?? [])
                let interfaces = (typeJSON["interfaces"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
                let possibleTypes = (typeJSON["possibleTypes"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
                typesByName[name] = GraphQLTypeDescriptor(
                    name: name,
                    kind: kind,
                    description: typeJSON["description"] as? String,
                    fields: fields,
                    inputFields: inputFields,
                    enumValues: enumValues,
                    interfaces: interfaces,
                    possibleTypes: possibleTypes
                )
            }
        }

        var directivesByName: [String: GraphQLDirectiveDescriptor] = [:]
        if let directives = schemaObject["directives"] as? [[String: Any]] {
            for directiveJSON in directives {
                guard let name = directiveJSON["name"] as? String else { continue }
                let args = parseInputFields(directiveJSON["args"] as? [[String: Any]] ?? []).map {
                    GraphQLArgumentDescriptor(
                        name: $0.name,
                        typeName: $0.typeName,
                        defaultValue: $0.defaultValue,
                        description: $0.description,
                        isDeprecated: $0.isDeprecated,
                        deprecationReason: nil
                    )
                }
                directivesByName[name] = GraphQLDirectiveDescriptor(
                    name: name,
                    description: directiveJSON["description"] as? String,
                    locations: directiveJSON["locations"] as? [String] ?? [],
                    arguments: args
                )
            }
        }

        if typesByName.count > SchemaResourceLimits.maxGraphQLTypeCount {
            throw GraphQLLanguageError.limitExceeded("Schema exceeds maximum type count.")
        }

        return GraphQLSchemaSnapshot(
            id: SchemaSnapshotID(),
            queryType: queryType,
            mutationType: mutationType,
            subscriptionType: subscriptionType,
            typesByName: typesByName,
            directivesByName: directivesByName
        )
    }

    private func namedTypeID(from object: [String: Any]?) -> GraphQLNamedTypeID? {
        guard let name = object?["name"] as? String else { return nil }
        return GraphQLNamedTypeID(name: name)
    }

    private func mapKind(_ raw: String?) -> GraphQLTypeDescriptor.Kind {
        switch raw {
        case "SCALAR": return .scalar
        case "OBJECT": return .object
        case "INTERFACE": return .interface
        case "UNION": return .union
        case "ENUM": return .enumType
        case "INPUT_OBJECT": return .inputObject
        default: return .scalar
        }
    }

    private func parseFields(_ fields: [[String: Any]]) -> [GraphQLFieldDescriptor] {
        fields.compactMap { field in
            guard let name = field["name"] as? String else { return nil }
            let args = parseInputFields(field["args"] as? [[String: Any]] ?? []).map {
                GraphQLArgumentDescriptor(
                    name: $0.name,
                    typeName: $0.typeName,
                    defaultValue: $0.defaultValue,
                    description: $0.description,
                    isDeprecated: $0.isDeprecated,
                    deprecationReason: nil
                )
            }
            return GraphQLFieldDescriptor(
                name: name,
                typeName: renderTypeRef(field["type"] as? [String: Any]),
                description: field["description"] as? String,
                arguments: args,
                isDeprecated: field["isDeprecated"] as? Bool ?? false,
                deprecationReason: field["deprecationReason"] as? String
            )
        }
    }

    private func parseInputFields(_ fields: [[String: Any]]) -> [GraphQLInputFieldDescriptor] {
        fields.compactMap { field in
            guard let name = field["name"] as? String else { return nil }
            return GraphQLInputFieldDescriptor(
                name: name,
                typeName: renderTypeRef(field["type"] as? [String: Any]),
                description: field["description"] as? String,
                defaultValue: field["defaultValue"] as? String,
                isDeprecated: false
            )
        }
    }

    private func parseEnumValues(_ values: [[String: Any]]) -> [GraphQLEnumValueDescriptor] {
        values.compactMap { value in
            guard let name = value["name"] as? String else { return nil }
            return GraphQLEnumValueDescriptor(
                name: name,
                description: value["description"] as? String,
                isDeprecated: value["isDeprecated"] as? Bool ?? false,
                deprecationReason: value["deprecationReason"] as? String
            )
        }
    }

    private func renderTypeRef(_ typeJSON: [String: Any]?) -> String {
        guard let typeJSON else { return "String" }
        let kind = typeJSON["kind"] as? String
        if kind == "NON_NULL" {
            return renderTypeRef(typeJSON["ofType"] as? [String: Any]) + "!"
        }
        if kind == "LIST" {
            return "[\(renderTypeRef(typeJSON["ofType"] as? [String: Any]))]"
        }
        return typeJSON["name"] as? String ?? "String"
    }
}

// MARK: - Document parser

private struct GraphQLDocumentParser {
    let source: String

    func parse() throws -> GraphQLDocument {
        var lexer = GraphQLLexer(source: source)
        let tokens = lexer.tokenize()
        var cursor = GraphQLTokenCursor(tokens: tokens)

        var operations: [GraphQLOperationInfo] = []
        var fragmentNames: [String] = []

        while !cursor.match(.eof) {
            _ = cursor.parseDescription()
            var kind: GraphQLOperationInfo.Kind = .query
            if cursor.matchName("query") {
                try cursor.expectName("query")
                kind = .query
            } else if cursor.matchName("mutation") {
                try cursor.expectName("mutation")
                kind = .mutation
            } else if cursor.matchName("subscription") {
                try cursor.expectName("subscription")
                kind = .subscription
            } else if cursor.matchName("fragment") {
                try cursor.expectName("fragment")
                let name = try cursor.parseName()
                fragmentNames.append(name)
                try cursor.expectName("on")
                _ = try cursor.parseName()
                try skipSelectionSet(&cursor)
                continue
            } else if cursor.match(.braceOpen) {
                kind = .query
            } else if case .name = cursor.current.kind {
                cursor.advance()
                continue
            } else {
                cursor.advance()
                continue
            }

            var operationName: String?
            if case .name(let value) = cursor.current.kind, value != "{" {
                operationName = value
                cursor.advance()
            }

            var variableDefinitions: [GraphQLVariableDefinition] = []
            if cursor.skip(kind: .parenOpen) {
                while !cursor.match(.parenClose) {
                    try cursor.expect(.dollar)
                    let varName = try cursor.parseName()
                    try cursor.expect(.colon)
                    let typeName = try cursor.parseTypeReference()
                    var defaultValue: String?
                    if cursor.skip(kind: .equals) {
                        defaultValue = try cursor.parseDefaultValue()
                    }
                    variableDefinitions.append(
                        GraphQLVariableDefinition(name: varName, typeName: typeName, defaultValue: defaultValue)
                    )
                }
                try cursor.expect(.parenClose)
            }

            try skipSelectionSet(&cursor)
            operations.append(
                GraphQLOperationInfo(kind: kind, name: operationName, variableDefinitions: variableDefinitions)
            )
        }

        return GraphQLDocument(source: source, operations: operations, fragmentNames: fragmentNames)
    }

    private func skipSelectionSet(_ cursor: inout GraphQLTokenCursor) throws {
        try cursor.expect(.braceOpen)
        while !cursor.match(.braceClose) {
            if cursor.skip(kind: .ellipsis) {
                try cursor.expectName("on")
                _ = try cursor.parseName()
            }
            _ = try cursor.parseName()
            if cursor.skip(kind: .parenOpen) {
                while !cursor.match(.parenClose) {
                    _ = try cursor.parseName()
                    try cursor.expect(.colon)
                    _ = try cursor.parseDefaultValue()
                }
                try cursor.expect(.parenClose)
            }
            if cursor.match(.braceOpen) {
                try skipSelectionSet(&cursor)
            }
            _ = try? cursor.parseDirectivesConstant()
        }
        try cursor.expect(.braceClose)
    }
}

// MARK: - Syntax checker

private struct GraphQLSyntaxChecker {
    let source: String

    func diagnostics() -> [EditorDiagnostic] {
        var diagnostics: [EditorDiagnostic] = []
        var stack: [(Character, Int)] = []
        let pairs: [Character: Character] = ["(": ")", "{": "}", "[": "]"]
        let closers: Set<Character> = [")", "}", "]"]
        let openers: Set<Character> = ["(", "{", "["]

        var inString = false
        var inBlockString = false
        var escaped = false
        var index = source.startIndex

        while index < source.endIndex {
            let char = source[index]
            let offset = source.utf16.distance(from: source.startIndex, to: index)

            if inBlockString {
                if char == "\"" && peek(from: index, count: 3) == "\"\"\"" {
                    inBlockString = false
                    index = source.index(index, offsetBy: 3)
                    continue
                }
                index = source.index(after: index)
                continue
            }

            if inString {
                if escaped {
                    escaped = false
                } else if char == "\\" {
                    escaped = true
                } else if char == "\"" {
                    inString = false
                }
                index = source.index(after: index)
                continue
            }

            if char == "\"" {
                if peek(from: index, count: 3) == "\"\"\"" {
                    inBlockString = true
                    index = source.index(index, offsetBy: 3)
                    continue
                }
                inString = true
                index = source.index(after: index)
                continue
            }

            if char == "#" {
                while index < source.endIndex, source[index] != "\n" {
                    index = source.index(after: index)
                }
                continue
            }

            if openers.contains(char) {
                stack.append((char, offset))
            } else if closers.contains(char) {
                if let (opener, openOffset) = stack.popLast(), pairs[opener] == char {
                    // matched
                } else {
                    diagnostics.append(
                        EditorDiagnostic(
                            severity: .error,
                            message: "Unmatched '\(char)'",
                            range: TextRange(location: offset, length: 1),
                            source: "graphql"
                        )
                    )
                }
            }

            index = source.index(after: index)
        }

        for (opener, openOffset) in stack.reversed() {
            diagnostics.append(
                EditorDiagnostic(
                    severity: .error,
                    message: "Unmatched '\(opener)'",
                    range: TextRange(location: openOffset, length: 1),
                    source: "graphql"
                )
            )
        }

        if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            diagnostics.append(
                EditorDiagnostic(
                    severity: .error,
                    message: "Document is empty",
                    source: "graphql"
                )
            )
        }

        return diagnostics
    }

    private func peek(from index: String.Index, count: Int) -> String {
        var cursor = index
        var result = ""
        for _ in 0..<count {
            guard cursor < source.endIndex else { return result }
            result.append(source[cursor])
            cursor = source.index(after: cursor)
        }
        return result
    }
}

// MARK: - Validation

private struct GraphQLDocumentValidator {
    let document: GraphQLDocument
    let schema: GraphQLSchemaSnapshot

    func validate() -> [EditorDiagnostic] {
        var diagnostics: [EditorDiagnostic] = []
        var lexer = GraphQLLexer(source: document.source)
        let tokens = lexer.tokenize()
        var cursor = GraphQLTokenCursor(tokens: tokens)

        while !cursor.match(.eof) {
            _ = cursor.parseDescription()
            var kind: GraphQLOperationInfo.Kind = .query
            if cursor.matchName("query") {
                try? cursor.expectName("query")
                kind = .query
            } else if cursor.matchName("mutation") {
                try? cursor.expectName("mutation")
                kind = .mutation
            } else if cursor.matchName("subscription") {
                try? cursor.expectName("subscription")
                kind = .subscription
            } else if cursor.matchName("fragment") {
                skipFragment(&cursor)
                continue
            } else if cursor.match(.braceOpen) {
                kind = .query
            } else {
                cursor.advance()
                continue
            }

            if case .name(let value) = cursor.current.kind, value != "{" {
                cursor.advance()
            }
            skipVariableDefinitions(&cursor)
            guard let rootTypeName = rootTypeName(for: kind) else {
                skipSelectionSet(&cursor)
                continue
            }
            diagnostics.append(contentsOf: validateSelectionSet(&cursor, parentTypeName: rootTypeName))
        }

        return diagnostics
    }

    private func rootTypeName(for kind: GraphQLOperationInfo.Kind) -> String? {
        switch kind {
        case .query: return schema.queryType?.name
        case .mutation: return schema.mutationType?.name
        case .subscription: return schema.subscriptionType?.name
        }
    }

    private func skipVariableDefinitions(_ cursor: inout GraphQLTokenCursor) {
        guard cursor.skip(kind: .parenOpen) else { return }
        while !cursor.match(.parenClose) {
            cursor.advance()
        }
        cursor.advance()
    }

    private func skipFragment(_ cursor: inout GraphQLTokenCursor) {
        cursor.advance()
        cursor.advance()
        if cursor.matchName("on") {
            cursor.advance()
            cursor.advance()
        }
        skipSelectionSet(&cursor)
    }

    private func skipSelectionSet(_ cursor: inout GraphQLTokenCursor) {
        guard cursor.skip(kind: .braceOpen) else { return }
        while !cursor.match(.braceClose) {
            if cursor.skip(kind: .ellipsis) {
                cursor.advance()
                cursor.advance()
            }
            cursor.advance()
            if cursor.skip(kind: .parenOpen) {
                while !cursor.match(.parenClose) { cursor.advance() }
                cursor.advance()
            }
            if cursor.match(.braceOpen) {
                skipSelectionSet(&cursor)
            }
            while cursor.skip(kind: .at) {
                cursor.advance()
                if cursor.skip(kind: .parenOpen) {
                    while !cursor.match(.parenClose) { cursor.advance() }
                    cursor.advance()
                }
            }
        }
        cursor.advance()
    }

    private func validateSelectionSet(
        _ cursor: inout GraphQLTokenCursor,
        parentTypeName: String
    ) -> [EditorDiagnostic] {
        var diagnostics: [EditorDiagnostic] = []
        guard cursor.skip(kind: .braceOpen) else { return diagnostics }

        while !cursor.match(.braceClose) {
            if cursor.skip(kind: .ellipsis) {
                try? cursor.expectName("on")
                _ = try? cursor.parseName()
                continue
            }

            guard case .name(let fieldName) = cursor.current.kind else {
                cursor.advance()
                continue
            }
            let fieldOffset = cursor.current.startUTF16
            cursor.advance()

            if fieldName.hasPrefix("__") {
                skipFieldTail(&cursor)
                continue
            }

            guard let parentType = schema.type(named: parentTypeName) else {
                skipFieldTail(&cursor)
                continue
            }

            let availableFields = mergedFields(for: parentType)
            if let field = availableFields.first(where: { $0.name == fieldName }) {
                skipFieldArguments(&cursor)
                if cursor.match(.braceOpen) {
                    let childType = GraphQLTypeNameResolver.namedType(from: field.typeName)
                    diagnostics.append(contentsOf: validateSelectionSet(&cursor, parentTypeName: childType))
                } else {
                    skipFieldTail(&cursor)
                }
            } else {
                diagnostics.append(
                    EditorDiagnostic(
                        severity: .error,
                        message: "Unknown field '\(fieldName)' on type '\(parentTypeName)'",
                        range: TextRange(location: fieldOffset, length: fieldName.utf16.count),
                        source: "graphql"
                    )
                )
                skipFieldTail(&cursor)
            }
        }
        cursor.advance()
        return diagnostics
    }

    private func skipFieldArguments(_ cursor: inout GraphQLTokenCursor) {
        guard cursor.skip(kind: .parenOpen) else { return }
        while !cursor.match(.parenClose) {
            cursor.advance()
        }
        cursor.advance()
    }

    private func skipFieldTail(_ cursor: inout GraphQLTokenCursor) {
        skipFieldArguments(&cursor)
        if cursor.match(.braceOpen) {
            skipSelectionSet(&cursor)
        }
        while cursor.skip(kind: .at) {
            cursor.advance()
            if cursor.skip(kind: .parenOpen) {
                while !cursor.match(.parenClose) { cursor.advance() }
                cursor.advance()
            }
        }
    }

    private func mergedFields(for type: GraphQLTypeDescriptor) -> [GraphQLFieldDescriptor] {
        var fields = type.fields
        for interfaceName in type.interfaces {
            if let interfaceType = schema.type(named: interfaceName) {
                fields.append(contentsOf: interfaceType.fields)
            }
        }
        return fields
    }
}

// MARK: - Type name resolver

enum GraphQLTypeNameResolver {
    static func namedType(from typeReference: String) -> String {
        var remaining = typeReference.trimmingCharacters(in: .whitespacesAndNewlines)
        if remaining.hasPrefix("[") {
            remaining = String(remaining.dropFirst())
            if let closeIndex = remaining.firstIndex(of: "]") {
                remaining = String(remaining[..<closeIndex])
            }
            return namedType(from: remaining)
        }
        if remaining.hasSuffix("!") {
            remaining.removeLast()
        }
        return remaining
    }

    static func isList(_ typeReference: String) -> Bool {
        typeReference.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[")
    }
}

// MARK: - Completions

private struct GraphQLCompletionProvider {
    let document: String
    let cursorUTF16Offset: Int
    let schema: GraphQLSchemaSnapshot

    func completions() -> [CompletionItem] {
        let prefix = prefixBeforeCursor()
        let partial = currentPartialToken(in: prefix)

        if let enumTypeName = enumContext(in: prefix) {
            return enumCompletions(typeName: enumTypeName, partial: partial)
        }

        if let inputTypeName = inputObjectContext(in: prefix) {
            return inputFieldCompletions(typeName: inputTypeName, partial: partial)
        }

        guard let typeName = selectionSetTypeName(in: prefix) else {
            return rootFieldCompletions(partial: partial)
        }

        return fieldCompletions(typeName: typeName, partial: partial)
    }

    private func prefixBeforeCursor() -> String {
        guard cursorUTF16Offset > 0 else { return "" }
        let utf16 = document.utf16
        guard cursorUTF16Offset <= utf16.count else { return document }
        let index = utf16.index(utf16.startIndex, offsetBy: cursorUTF16Offset)
        guard let stringIndex = index.samePosition(in: document) else { return document }
        return String(document[..<stringIndex])
    }

    private func currentPartialToken(in prefix: String) -> String {
        guard let last = prefix.last, last.isLetter || last == "_" else { return "" }
        let parts = prefix.split { !$0.isLetter && $0 != "_" }
        return parts.last.map(String.init) ?? ""
    }

    private func selectionSetTypeName(in prefix: String) -> String? {
        var tokens: [String] = []
        var lexer = GraphQLLexer(source: prefix)
        let rawTokens = lexer.tokenize()
        for token in rawTokens where token.kind != .eof {
            switch token.kind {
            case .name(let value): tokens.append(value)
            case .braceOpen: tokens.append("{")
            case .braceClose: tokens.append("}")
            case .parenOpen: tokens.append("(")
            case .parenClose: tokens.append(")")
            default: break
            }
        }

        var typeName = schema.queryType?.name ?? "Query"
        var expectingField = false
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if token == "query" || token == "mutation" || token == "subscription" {
                if token == "mutation" {
                    typeName = schema.mutationType?.name ?? typeName
                } else if token == "subscription" {
                    typeName = schema.subscriptionType?.name ?? typeName
                } else {
                    typeName = schema.queryType?.name ?? typeName
                }
                index += 1
                if index < tokens.count, tokens[index] != "{", tokens[index] != "(" {
                    index += 1
                }
                continue
            }
            if token == "(" {
                index += 1
                while index < tokens.count, tokens[index] != ")" { index += 1 }
                if index < tokens.count { index += 1 }
                continue
            }
            if token == "{" {
                expectingField = true
                index += 1
                continue
            }
            if token == "}" {
                expectingField = false
                index += 1
                continue
            }
            if expectingField, token != "on" {
                if let type = schema.type(named: typeName),
                   let field = type.fields.first(where: { $0.name == token }) {
                    typeName = GraphQLTypeNameResolver.namedType(from: field.typeName)
                }
                expectingField = false
            }
            index += 1
        }

        if prefix.last == "{" || prefix.hasSuffix("{ ") || prefix.hasSuffix("{\n") {
            return typeName
        }

        if !currentPartialToken(in: prefix).isEmpty, prefix.contains("{") {
            return typeName
        }

        return nil
    }

    private func enumContext(in prefix: String) -> String? {
        guard let openIndex = prefix.lastIndex(of: "{") else { return nil }
        let tail = prefix[openIndex...]
        guard tail.contains(":") else { return nil }
        let segments = tail.split(separator: ":", maxSplits: 1)
        guard segments.count == 2 else { return nil }
        let argPart = segments[0].split { $0.isWhitespace || $0 == "{" || $0 == "(" || $0 == "," }
        guard let argName = argPart.last.map(String.init) else { return nil }
        let before = String(prefix[..<openIndex])
        guard let fieldName = fieldNameBeforeArguments(in: before) else { return nil }
        guard let parentTypeName = selectionSetTypeName(in: before) ?? schema.queryType?.name else { return nil }
        guard let parentType = schema.type(named: parentTypeName),
              let field = parentType.fields.first(where: { $0.name == fieldName }),
              let arg = field.arguments.first(where: { $0.name == argName }) else { return nil }
        let named = GraphQLTypeNameResolver.namedType(from: arg.typeName)
        guard schema.type(named: named)?.kind == .enumType else { return nil }
        return named
    }

    private func fieldNameBeforeArguments(in prefix: String) -> String? {
        var tokens: [String] = []
        var lexer = GraphQLLexer(source: prefix)
        for token in lexer.tokenize() where token.kind != .eof {
            if case .name(let value) = token.kind { tokens.append(value) }
        }
        return tokens.last
    }

    private func inputObjectContext(in prefix: String) -> String? {
        guard prefix.contains("{"), prefix.contains(":") else { return nil }
        return nil
    }

    private func rootFieldCompletions(partial: String) -> [CompletionItem] {
        fieldCompletions(typeName: schema.queryType?.name ?? "Query", partial: partial)
    }

    private func fieldCompletions(typeName: String, partial: String) -> [CompletionItem] {
        guard let type = schema.type(named: typeName) else { return [] }
        return type.fields
            .filter { partial.isEmpty || $0.name.hasPrefix(partial) }
            .map {
                CompletionItem(
                    label: $0.name,
                    detail: $0.typeName,
                    documentation: $0.description,
                    kind: .field,
                    deprecated: $0.isDeprecated
                )
            }
    }

    private func enumCompletions(typeName: String, partial: String) -> [CompletionItem] {
        guard let type = schema.type(named: typeName), type.kind == .enumType else { return [] }
        return type.enumValues
            .filter { partial.isEmpty || $0.name.hasPrefix(partial) }
            .map {
                CompletionItem(
                    label: $0.name,
                    documentation: $0.description,
                    kind: .enumCase,
                    deprecated: $0.isDeprecated
                )
            }
    }

    private func inputFieldCompletions(typeName: String, partial: String) -> [CompletionItem] {
        guard let type = schema.type(named: typeName), type.kind == .inputObject else { return [] }
        return type.inputFields
            .filter { partial.isEmpty || $0.name.hasPrefix(partial) }
            .map {
                CompletionItem(
                    label: $0.name,
                    detail: $0.typeName,
                    documentation: $0.description,
                    kind: .field,
                    deprecated: $0.isDeprecated
                )
            }
    }
}

// MARK: - SDL serialization

enum GraphQLSDLSerializer {
    static func render(_ schema: GraphQLSchemaSnapshot) -> String {
        var lines: [String] = []
        if let query = schema.queryType?.name {
            var schemaLine = "schema { query: \(query)"
            if let mutation = schema.mutationType?.name {
                schemaLine += " mutation: \(mutation)"
            }
            if let subscription = schema.subscriptionType?.name {
                schemaLine += " subscription: \(subscription)"
            }
            schemaLine += " }"
            lines.append(schemaLine)
            lines.append("")
        }

        let sortedNames = schema.typesByName.keys.sorted()
        for name in sortedNames {
            guard let type = schema.typesByName[name] else { continue }
            if ["Query", "Mutation", "Subscription"].contains(name),
               schema.queryType?.name == name || schema.mutationType?.name == name || schema.subscriptionType?.name == name {
                // still render below
            }
            if let description = type.description {
                lines.append("\"\(description.replacingOccurrences(of: "\"", with: "\\\""))\"")
            }
            switch type.kind {
            case .scalar:
                lines.append("scalar \(name)")
            case .object:
                lines.append(renderObject(type, keyword: "type"))
            case .interface:
                lines.append(renderObject(type, keyword: "interface"))
            case .union:
                lines.append("union \(name) = \(type.possibleTypes.joined(separator: " | "))")
            case .enumType:
                lines.append("enum \(name) {")
                for value in type.enumValues {
                    lines.append("  \(value.name)")
                }
                lines.append("}")
            case .inputObject:
                lines.append("input \(name) {")
                for field in type.inputFields {
                    let defaultSuffix = field.defaultValue.map { " = \($0)" } ?? ""
                    lines.append("  \(field.name): \(field.typeName)\(defaultSuffix)")
                }
                lines.append("}")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private static func renderObject(_ type: GraphQLTypeDescriptor, keyword: String) -> String {
        var header = "\(keyword) \(type.name)"
        if !type.interfaces.isEmpty {
            header += " implements \(type.interfaces.joined(separator: " & "))"
        }
        var body = [header + " {"]
        for field in type.fields {
            let args = field.arguments.isEmpty
                ? ""
                : "(\(field.arguments.map { "\($0.name): \($0.typeName)" }.joined(separator: ", ")))"
            body.append("  \(field.name)\(args): \(field.typeName)")
        }
        body.append("}")
        return body.joined(separator: "\n")
    }
}
