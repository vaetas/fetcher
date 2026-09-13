import Foundation

// MARK: - Wire codec

enum ProtobufWireType: Int {
    case varint = 0
    case fixed64 = 1
    case lengthDelimited = 2
    case startGroup = 3
    case endGroup = 4
    case fixed32 = 5
}

enum ProtobufWireError: Error, Sendable {
    case truncated
    case invalidTag
    case unsupportedWireType(Int)
    case invalidUTF8
    case overflow
}

struct ProtobufReader {
    private let data: Data
    private var offset: Int = 0

    init(data: Data) {
        self.data = data
    }

    var isAtEnd: Bool { offset >= data.count }
    var remaining: Int { data.count - offset }

    mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while shift <= 63 {
            guard offset < data.count else { throw ProtobufWireError.truncated }
            let byte = data[offset]
            offset += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
        }
        throw ProtobufWireError.overflow
    }

    mutating func readTag() throws -> (fieldNumber: Int, wireType: Int) {
        let tag = try readVarint()
        let wireType = Int(tag & 0x7)
        let fieldNumber = Int(tag >> 3)
        guard fieldNumber > 0 else { throw ProtobufWireError.invalidTag }
        return (fieldNumber, wireType)
    }

    mutating func readLengthDelimited() throws -> Data {
        let length = Int(try readVarint())
        guard length >= 0, offset + length <= data.count else { throw ProtobufWireError.truncated }
        let slice = data.subdata(in: offset ..< offset + length)
        offset += length
        return slice
    }

    mutating func readFixed32() throws -> UInt32 {
        guard offset + 4 <= data.count else { throw ProtobufWireError.truncated }
        let value = data.withUnsafeBytes { raw -> UInt32 in
            raw.load(fromByteOffset: offset, as: UInt32.self)
        }
        offset += 4
        return UInt32(littleEndian: value)
    }

    mutating func readFixed64() throws -> UInt64 {
        guard offset + 8 <= data.count else { throw ProtobufWireError.truncated }
        let value = data.withUnsafeBytes { raw -> UInt64 in
            raw.load(fromByteOffset: offset, as: UInt64.self)
        }
        offset += 8
        return UInt64(littleEndian: value)
    }

    mutating func skipField(wireType: Int) throws {
        switch wireType {
        case ProtobufWireType.varint.rawValue:
            _ = try readVarint()
        case ProtobufWireType.fixed64.rawValue:
            _ = try readFixed64()
        case ProtobufWireType.lengthDelimited.rawValue:
            _ = try readLengthDelimited()
        case ProtobufWireType.fixed32.rawValue:
            _ = try readFixed32()
        case ProtobufWireType.startGroup.rawValue, ProtobufWireType.endGroup.rawValue:
            throw ProtobufWireError.unsupportedWireType(wireType)
        default:
            throw ProtobufWireError.unsupportedWireType(wireType)
        }
    }
}

struct ProtobufWriter {
    private(set) var data = Data()

    mutating func writeTag(fieldNumber: Int, wireType: Int) {
        writeVarint(UInt64((fieldNumber << 3) | wireType))
    }

    mutating func writeVarint(_ value: UInt64) {
        var v = value
        repeat {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 { byte |= 0x80 }
            data.append(byte)
        } while v != 0
    }

    mutating func writeLengthDelimited(_ bytes: Data) {
        writeVarint(UInt64(bytes.count))
        data.append(bytes)
    }

    mutating func writeFixed32(_ value: UInt32) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    mutating func writeFixed64(_ value: UInt64) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    mutating func writeString(fieldNumber: Int, _ string: String) {
        guard let bytes = string.data(using: .utf8) else { return }
        writeTag(fieldNumber: fieldNumber, wireType: ProtobufWireType.lengthDelimited.rawValue)
        writeLengthDelimited(bytes)
    }

    mutating func writeBytes(fieldNumber: Int, _ bytes: Data) {
        writeTag(fieldNumber: fieldNumber, wireType: ProtobufWireType.lengthDelimited.rawValue)
        writeLengthDelimited(bytes)
    }

    mutating func writeBool(fieldNumber: Int, _ value: Bool) {
        writeTag(fieldNumber: fieldNumber, wireType: ProtobufWireType.varint.rawValue)
        writeVarint(value ? 1 : 0)
    }

    mutating func writeInt32(fieldNumber: Int, _ value: Int32) {
        writeTag(fieldNumber: fieldNumber, wireType: ProtobufWireType.varint.rawValue)
        writeVarint(UInt64(bitPattern: Int64(value)))
    }

    mutating func writeInt64(fieldNumber: Int, _ value: Int64) {
        writeTag(fieldNumber: fieldNumber, wireType: ProtobufWireType.varint.rawValue)
        writeVarint(UInt64(bitPattern: value))
    }

    mutating func writeUInt32(fieldNumber: Int, _ value: UInt32) {
        writeTag(fieldNumber: fieldNumber, wireType: ProtobufWireType.varint.rawValue)
        writeVarint(UInt64(value))
    }

    mutating func writeDouble(fieldNumber: Int, _ value: Double) {
        writeTag(fieldNumber: fieldNumber, wireType: ProtobufWireType.fixed64.rawValue)
        writeFixed64(value.bitPattern)
    }

    mutating func writeFloat(fieldNumber: Int, _ value: Float) {
        writeTag(fieldNumber: fieldNumber, wireType: ProtobufWireType.fixed32.rawValue)
        writeFixed32(value.bitPattern)
    }

    mutating func writeEmbeddedMessage(fieldNumber: Int, _ messageData: Data) {
        writeTag(fieldNumber: fieldNumber, wireType: ProtobufWireType.lengthDelimited.rawValue)
        writeLengthDelimited(messageData)
    }
}

// MARK: - Descriptor parsing

private struct RawFieldDescriptor {
    var name: String = ""
    var number: Int = 0
    var label: Int = 1
    var type: Int = 0
    var typeName: String = ""
    var jsonName: String = ""
    var oneofIndex: Int?
    var options: Data?
}

private struct RawEnumValueDescriptor {
    var name: String = ""
    var number: Int = 0
}

private struct RawEnumDescriptor {
    var name: String = ""
    var values: [RawEnumValueDescriptor] = []
}

private struct RawMessageDescriptor {
    var name: String = ""
    var fields: [RawFieldDescriptor] = []
    var nestedTypes: [RawMessageDescriptor] = []
    var enumTypes: [RawEnumDescriptor] = []
    var options: Data?
}

private struct RawMethodDescriptor {
    var name: String = ""
    var inputType: String = ""
    var outputType: String = ""
    var clientStreaming: Bool = false
    var serverStreaming: Bool = false
}

private struct RawServiceDescriptor {
    var name: String = ""
    var methods: [RawMethodDescriptor] = []
}

private struct RawFileDescriptor {
    var name: String = ""
    var package: String = ""
    var dependencies: [String] = []
    var messageTypes: [RawMessageDescriptor] = []
    var enumTypes: [RawEnumDescriptor] = []
    var services: [RawServiceDescriptor] = []
}

private enum DescriptorFieldNumbers {
    static let fileDescriptorProto = 1
    static let name = 1
    static let package = 2
    static let dependency = 3
    static let messageType = 4
    static let enumType = 5
    static let service = 6
    static let field = 2
    static let nestedType = 3
    static let enumTypeNested = 4
    static let number = 3
    static let label = 4
    static let type = 5
    static let typeName = 6
    static let oneofIndex = 9
    static let jsonName = 10
    static let options = 7
    static let method = 2
    static let inputType = 2
    static let outputType = 3
    static let clientStreaming = 5
    static let serverStreaming = 6
    static let value = 2
    static let mapEntry = 7
}

private enum FieldDescriptorProtoType: Int {
    case double = 1, float, int64, uint64, int32, fixed64, fixed32, bool, string, group, message, bytes, uint32, enumType, sfixed32, sfixed64, sint32, sint64
}

private enum FieldDescriptorProtoLabel: Int {
    case optional = 1, required, repeated
}

private func parseMessageDescriptor(_ data: Data) throws -> RawMessageDescriptor {
    var reader = ProtobufReader(data: data)
    var message = RawMessageDescriptor()
    while !reader.isAtEnd {
        let (fieldNumber, wireType) = try reader.readTag()
        switch fieldNumber {
        case DescriptorFieldNumbers.name:
            let bytes = try reader.readLengthDelimited()
            message.name = String(data: bytes, encoding: .utf8) ?? ""
        case DescriptorFieldNumbers.field:
            let bytes = try reader.readLengthDelimited()
            message.fields.append(try parseFieldDescriptor(bytes))
        case DescriptorFieldNumbers.nestedType:
            let bytes = try reader.readLengthDelimited()
            message.nestedTypes.append(try parseMessageDescriptor(bytes))
        case DescriptorFieldNumbers.enumTypeNested:
            let bytes = try reader.readLengthDelimited()
            message.enumTypes.append(try parseEnumDescriptor(bytes))
        case DescriptorFieldNumbers.options:
            message.options = try reader.readLengthDelimited()
        default:
            try reader.skipField(wireType: wireType)
        }
    }
    return message
}

private func parseFieldDescriptor(_ data: Data) throws -> RawFieldDescriptor {
    var reader = ProtobufReader(data: data)
    var field = RawFieldDescriptor()
    while !reader.isAtEnd {
        let (fieldNumber, wireType) = try reader.readTag()
        switch fieldNumber {
        case DescriptorFieldNumbers.name:
            let bytes = try reader.readLengthDelimited()
            field.name = String(data: bytes, encoding: .utf8) ?? ""
        case DescriptorFieldNumbers.number:
            field.number = Int(try reader.readVarint())
        case DescriptorFieldNumbers.label:
            field.label = Int(try reader.readVarint())
        case DescriptorFieldNumbers.type:
            field.type = Int(try reader.readVarint())
        case DescriptorFieldNumbers.typeName:
            let bytes = try reader.readLengthDelimited()
            field.typeName = String(data: bytes, encoding: .utf8) ?? ""
        case DescriptorFieldNumbers.oneofIndex:
            field.oneofIndex = Int(try reader.readVarint())
        case DescriptorFieldNumbers.jsonName:
            let bytes = try reader.readLengthDelimited()
            field.jsonName = String(data: bytes, encoding: .utf8) ?? ""
        case DescriptorFieldNumbers.options:
            field.options = try reader.readLengthDelimited()
        default:
            try reader.skipField(wireType: wireType)
        }
    }
    return field
}

private func parseEnumDescriptor(_ data: Data) throws -> RawEnumDescriptor {
    var reader = ProtobufReader(data: data)
    var enumDesc = RawEnumDescriptor()
    while !reader.isAtEnd {
        let (fieldNumber, wireType) = try reader.readTag()
        switch fieldNumber {
        case DescriptorFieldNumbers.name:
            let bytes = try reader.readLengthDelimited()
            enumDesc.name = String(data: bytes, encoding: .utf8) ?? ""
        case DescriptorFieldNumbers.value:
            let bytes = try reader.readLengthDelimited()
            enumDesc.values.append(try parseEnumValueDescriptor(bytes))
        default:
            try reader.skipField(wireType: wireType)
        }
    }
    return enumDesc
}

private func parseEnumValueDescriptor(_ data: Data) throws -> RawEnumValueDescriptor {
    var reader = ProtobufReader(data: data)
    var value = RawEnumValueDescriptor()
    while !reader.isAtEnd {
        let (fieldNumber, wireType) = try reader.readTag()
        switch fieldNumber {
        case DescriptorFieldNumbers.name:
            let bytes = try reader.readLengthDelimited()
            value.name = String(data: bytes, encoding: .utf8) ?? ""
        case DescriptorFieldNumbers.number:
            value.number = Int(try reader.readVarint())
        default:
            try reader.skipField(wireType: wireType)
        }
    }
    return value
}

private func parseServiceDescriptor(_ data: Data) throws -> RawServiceDescriptor {
    var reader = ProtobufReader(data: data)
    var service = RawServiceDescriptor()
    while !reader.isAtEnd {
        let (fieldNumber, wireType) = try reader.readTag()
        switch fieldNumber {
        case DescriptorFieldNumbers.name:
            let bytes = try reader.readLengthDelimited()
            service.name = String(data: bytes, encoding: .utf8) ?? ""
        case DescriptorFieldNumbers.method:
            let bytes = try reader.readLengthDelimited()
            service.methods.append(try parseMethodDescriptor(bytes))
        default:
            try reader.skipField(wireType: wireType)
        }
    }
    return service
}

private func parseMethodDescriptor(_ data: Data) throws -> RawMethodDescriptor {
    var reader = ProtobufReader(data: data)
    var method = RawMethodDescriptor()
    while !reader.isAtEnd {
        let (fieldNumber, wireType) = try reader.readTag()
        switch fieldNumber {
        case DescriptorFieldNumbers.name:
            let bytes = try reader.readLengthDelimited()
            method.name = String(data: bytes, encoding: .utf8) ?? ""
        case DescriptorFieldNumbers.inputType:
            let bytes = try reader.readLengthDelimited()
            method.inputType = String(data: bytes, encoding: .utf8) ?? ""
        case DescriptorFieldNumbers.outputType:
            let bytes = try reader.readLengthDelimited()
            method.outputType = String(data: bytes, encoding: .utf8) ?? ""
        case DescriptorFieldNumbers.clientStreaming:
            method.clientStreaming = try reader.readVarint() != 0
        case DescriptorFieldNumbers.serverStreaming:
            method.serverStreaming = try reader.readVarint() != 0
        default:
            try reader.skipField(wireType: wireType)
        }
    }
    return method
}

private func parseFileDescriptor(_ data: Data) throws -> RawFileDescriptor {
    var reader = ProtobufReader(data: data)
    var file = RawFileDescriptor()
    while !reader.isAtEnd {
        let (fieldNumber, wireType) = try reader.readTag()
        switch fieldNumber {
        case DescriptorFieldNumbers.name:
            let bytes = try reader.readLengthDelimited()
            file.name = String(data: bytes, encoding: .utf8) ?? ""
        case DescriptorFieldNumbers.package:
            let bytes = try reader.readLengthDelimited()
            file.package = String(data: bytes, encoding: .utf8) ?? ""
        case DescriptorFieldNumbers.dependency:
            let bytes = try reader.readLengthDelimited()
            if let dep = String(data: bytes, encoding: .utf8) {
                file.dependencies.append(dep)
            }
        case DescriptorFieldNumbers.messageType:
            let bytes = try reader.readLengthDelimited()
            file.messageTypes.append(try parseMessageDescriptor(bytes))
        case DescriptorFieldNumbers.enumType:
            let bytes = try reader.readLengthDelimited()
            file.enumTypes.append(try parseEnumDescriptor(bytes))
        case DescriptorFieldNumbers.service:
            let bytes = try reader.readLengthDelimited()
            file.services.append(try parseServiceDescriptor(bytes))
        default:
            try reader.skipField(wireType: wireType)
        }
    }
    return file
}

private func isMapEntryMessage(_ message: RawMessageDescriptor) -> Bool {
    guard let options = message.options else { return false }
    var reader = ProtobufReader(data: options)
    while !reader.isAtEnd {
        guard let tag = try? reader.readTag() else { return false }
        if tag.fieldNumber == DescriptorFieldNumbers.mapEntry {
            if let value = try? reader.readVarint(), value != 0 { return true }
        } else {
            try? reader.skipField(wireType: tag.wireType)
        }
    }
    return false
}

private func resolveTypeName(_ name: String, package: String) -> String {
    if name.hasPrefix(".") {
        return String(name.dropFirst())
    }
    if name.contains(".") {
        return name
    }
    return package.isEmpty ? name : "\(package).\(name)"
}

private func scalarTypeName(for type: Int) -> String {
    switch FieldDescriptorProtoType(rawValue: type) {
    case .double: "double"
    case .float: "float"
    case .int64, .sfixed64, .sint64: "int64"
    case .uint64, .fixed64: "uint64"
    case .int32, .sfixed32, .sint32: "int32"
    case .uint32, .fixed32: "uint32"
    case .bool: "bool"
    case .string: "string"
    case .bytes: "bytes"
    default: "unknown"
    }
}

// MARK: - Runtime

struct BuiltinDynamicProtobufRuntime: DynamicProtobufRuntime {
    enum RuntimeError: Error, LocalizedError {
        case invalidDescriptorSet(String)
        case unknownMessage(String)
        case unknownEnum(String)
        case invalidJSON(String)
        case typeMismatch(String, field: String)
        case unknownField(String)
        case encoding(String)

        var errorDescription: String? {
            switch self {
            case .invalidDescriptorSet(let detail): detail
            case .unknownMessage(let name): "Unknown message type '\(name)'."
            case .unknownEnum(let name): "Unknown enum type '\(name)'."
            case .invalidJSON(let detail): detail
            case .typeMismatch(let detail, let field): "\(field): \(detail)"
            case .unknownField(let name): "Unknown field '\(name)'."
            case .encoding(let detail): detail
            }
        }
    }

    func buildRegistry(descriptorSet: Data) throws -> ProtobufRegistry {
        let snapshot = try index(descriptorSet: descriptorSet)
        return ProtobufRegistry(snapshot: snapshot)
    }

    func index(descriptorSet: Data, id: SchemaSnapshotID = SchemaSnapshotID()) throws -> ProtobufSchemaSnapshot {
        var reader = ProtobufReader(data: descriptorSet)
        var rawFiles: [RawFileDescriptor] = []
        var descriptorCount = 0

        while !reader.isAtEnd {
            let (fieldNumber, wireType) = try reader.readTag()
            guard fieldNumber == DescriptorFieldNumbers.fileDescriptorProto else {
                try reader.skipField(wireType: wireType)
                continue
            }
            let bytes = try reader.readLengthDelimited()
            rawFiles.append(try parseFileDescriptor(bytes))
            descriptorCount += 1
            if descriptorCount > SchemaResourceLimits.maxProtobufDescriptorCount {
                throw RuntimeError.invalidDescriptorSet("Descriptor set exceeds descriptor count limit.")
            }
        }

        guard !rawFiles.isEmpty else {
            throw RuntimeError.invalidDescriptorSet("Descriptor set contains no file descriptors.")
        }

        var files: [ProtoFileDescriptor] = []
        var servicesByName: [String: ProtoServiceDescriptor] = [:]
        var messagesByName: [String: ProtoMessageDescriptor] = [:]
        var enumsByName: [String: ProtoEnumDescriptor] = [:]

        for rawFile in rawFiles {
            files.append(ProtoFileDescriptor(
                name: rawFile.name,
                package: rawFile.package,
                dependencies: rawFile.dependencies
            ))

            for rawEnum in rawFile.enumTypes {
                let fullName = resolveTypeName(rawEnum.name, package: rawFile.package)
                enumsByName[fullName] = ProtoEnumDescriptor(
                    fullName: fullName,
                    values: rawEnum.values.map {
                        ProtoEnumValueDescriptor(name: $0.name, number: $0.number, documentation: nil)
                    },
                    documentation: nil
                )
            }

            func indexMessages(_ messages: [RawMessageDescriptor], prefix: String) {
                for rawMessage in messages {
                    let fullName = prefix.isEmpty ? resolveTypeName(rawMessage.name, package: rawFile.package) : "\(prefix).\(rawMessage.name)"
                    let nestedNames = rawMessage.nestedTypes.map { "\(fullName).\($0.name)" }

                    var fields: [ProtoFieldDescriptor] = []
                    for rawField in rawMessage.fields {
                        let jsonName = rawField.jsonName.isEmpty ? rawField.name : rawField.jsonName
                        let label = FieldDescriptorProtoLabel(rawValue: rawField.label) ?? .optional
                        let fieldType = FieldDescriptorProtoType(rawValue: rawField.type)

                        var cardinality: ProtoFieldDescriptor.Cardinality = .optional
                        var typeName: String

                        if label == .repeated {
                            if fieldType == .message,
                               !rawField.typeName.isEmpty,
                               let entryMessage = rawMessage.nestedTypes.first(where: { resolveTypeName($0.name, package: rawFile.package) == resolveTypeName(rawField.typeName, package: rawFile.package) || $0.name == rawField.typeName.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }),
                               isMapEntryMessage(entryMessage) {
                                cardinality = .map
                                if let keyField = entryMessage.fields.first(where: { $0.number == 1 }),
                                   let valueField = entryMessage.fields.first(where: { $0.number == 2 }) {
                                    let keyType = FieldDescriptorProtoType(rawValue: keyField.type).map { scalarTypeName(for: $0.rawValue) } ?? keyField.typeName
                                    let valueType: String
                                    if FieldDescriptorProtoType(rawValue: valueField.type) == .message || FieldDescriptorProtoType(rawValue: valueField.type) == .enumType {
                                        valueType = resolveTypeName(valueField.typeName, package: rawFile.package)
                                    } else {
                                        valueType = scalarTypeName(for: valueField.type)
                                    }
                                    typeName = "map<\(keyType), \(valueType)>"
                                } else {
                                    typeName = resolveTypeName(rawField.typeName, package: rawFile.package)
                                }
                            } else {
                                cardinality = .repeated
                                if fieldType == .message || fieldType == .enumType {
                                    typeName = resolveTypeName(rawField.typeName, package: rawFile.package)
                                } else {
                                    typeName = scalarTypeName(for: rawField.type)
                                }
                            }
                        } else if label == .required {
                            cardinality = .required
                            if fieldType == .message || fieldType == .enumType {
                                typeName = resolveTypeName(rawField.typeName, package: rawFile.package)
                            } else {
                                typeName = scalarTypeName(for: rawField.type)
                            }
                        } else {
                            if fieldType == .message || fieldType == .enumType {
                                typeName = resolveTypeName(rawField.typeName, package: rawFile.package)
                            } else {
                                typeName = scalarTypeName(for: rawField.type)
                            }
                        }

                        fields.append(ProtoFieldDescriptor(
                            name: rawField.name,
                            jsonName: jsonName,
                            number: rawField.number,
                            typeName: typeName,
                            cardinality: cardinality,
                            oneofName: rawField.oneofIndex.map { "oneof_\($0)" },
                            documentation: nil,
                            isDeprecated: false
                        ))
                    }

                    for rawEnum in rawMessage.enumTypes {
                        let enumFullName = "\(fullName).\(rawEnum.name)"
                        enumsByName[enumFullName] = ProtoEnumDescriptor(
                            fullName: enumFullName,
                            values: rawEnum.values.map {
                                ProtoEnumValueDescriptor(name: $0.name, number: $0.number, documentation: nil)
                            },
                            documentation: nil
                        )
                    }

                    messagesByName[fullName] = ProtoMessageDescriptor(
                        fullName: fullName,
                        fields: fields.sorted { $0.number < $1.number },
                        nestedTypeNames: nestedNames,
                        documentation: nil
                    )

                    indexMessages(rawMessage.nestedTypes, prefix: fullName)
                }
            }

            indexMessages(rawFile.messageTypes, prefix: "")

            for rawService in rawFile.services {
                let serviceFullName = rawFile.package.isEmpty ? rawService.name : "\(rawFile.package).\(rawService.name)"
                let methods = rawService.methods.map { rawMethod in
                    ProtoMethodDescriptor(
                        serviceFullName: serviceFullName,
                        name: rawMethod.name,
                        inputType: ProtobufTypeID(fullName: resolveTypeName(rawMethod.inputType, package: rawFile.package)),
                        outputType: ProtobufTypeID(fullName: resolveTypeName(rawMethod.outputType, package: rawFile.package)),
                        clientStreaming: rawMethod.clientStreaming,
                        serverStreaming: rawMethod.serverStreaming,
                        documentation: nil
                    )
                }
                servicesByName[serviceFullName] = ProtoServiceDescriptor(
                    fullName: serviceFullName,
                    documentation: nil,
                    methods: methods
                )
            }
        }

        return ProtobufSchemaSnapshot(
            id: id,
            files: files,
            servicesByName: servicesByName,
            messagesByName: messagesByName,
            enumsByName: enumsByName,
            descriptorSetData: descriptorSet
        )
    }

    func validateJSON(
        _ json: String,
        messageType: ProtobufTypeID,
        registry: ProtobufRegistry
    ) -> [ProtobufDiagnostic] {
        do {
            let object = try parseJSONObject(json)
            return validateJSONObject(object, messageType: messageType, registry: registry, path: "$")
        } catch {
            return [ProtobufDiagnostic(message: error.localizedDescription)]
        }
    }

    func encodeProtoJSON(
        _ json: String,
        messageType: ProtobufTypeID,
        registry: ProtobufRegistry
    ) throws -> Data {
        let diagnostics = validateJSON(json, messageType: messageType, registry: registry)
        if let blocking = diagnostics.first {
            throw RuntimeError.invalidJSON(blocking.message)
        }
        let object = try parseJSONObject(json)
        var writer = ProtobufWriter()
        try encodeMessage(object, messageType: messageType, registry: registry, into: &writer)
        return writer.data
    }

    func decodeToProtoJSON(
        _ protobuf: Data,
        messageType: ProtobufTypeID,
        registry: ProtobufRegistry
    ) throws -> String {
        guard let descriptor = registry.snapshot.messagesByName[messageType.fullName] else {
            throw RuntimeError.unknownMessage(messageType.fullName)
        }
        var reader = ProtobufReader(data: protobuf)
        let object = try decodeMessage(from: &reader, descriptor: descriptor, registry: registry)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
        guard let text = String(data: data, encoding: .utf8) else {
            throw RuntimeError.encoding("Unable to encode decoded message as UTF-8 JSON.")
        }
        return text
    }

    // MARK: JSON validation

    private func parseJSONObject(_ json: String) throws -> [String: Any] {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = trimmed.isEmpty ? "{}" : trimmed
        guard let data = payload.data(using: .utf8) else {
            throw RuntimeError.invalidJSON("Message JSON is not valid UTF-8.")
        }
        let value = try JSONSerialization.jsonObject(with: data)
        guard let object = value as? [String: Any] else {
            throw RuntimeError.invalidJSON("Message JSON must be a JSON object.")
        }
        return object
    }

    private func validateJSONObject(
        _ object: [String: Any],
        messageType: ProtobufTypeID,
        registry: ProtobufRegistry,
        path: String
    ) -> [ProtobufDiagnostic] {
        guard let descriptor = registry.snapshot.messagesByName[messageType.fullName] else {
            return [ProtobufDiagnostic(message: "Unknown message type '\(messageType.fullName)'.")]
        }

        var diagnostics: [ProtobufDiagnostic] = []
        let knownJSONNames = Set(descriptor.fields.map(\.jsonName))

        for key in object.keys where !knownJSONNames.contains(key) {
            diagnostics.append(ProtobufDiagnostic(message: "Unknown field '\(key)' at \(path)."))
        }

        for field in descriptor.fields {
            let fieldPath = "\(path).\(field.jsonName)"
            guard let value = object[field.jsonName] else { continue }
            diagnostics.append(contentsOf: validateFieldValue(value, field: field, registry: registry, path: fieldPath))
        }

        return diagnostics
    }

    private func validateFieldValue(
        _ value: Any,
        field: ProtoFieldDescriptor,
        registry: ProtobufRegistry,
        path: String
    ) -> [ProtobufDiagnostic] {
        switch field.cardinality {
        case .repeated:
            guard let array = value as? [Any] else {
                return [ProtobufDiagnostic(message: "Expected array for repeated field at \(path).")]
            }
            return array.enumerated().flatMap { index, element in
                validateScalarOrMessage(element, typeName: field.typeName, registry: registry, path: "\(path)[\(index)]", allowNull: false)
            }
        case .map:
            guard let mapObject = value as? [String: Any] else {
                return [ProtobufDiagnostic(message: "Expected object for map field at \(path).")]
            }
            let (keyType, valueType) = parseMapTypes(field.typeName)
            return mapObject.flatMap { key, element -> [ProtobufDiagnostic] in
                var issues = validateMapKey(key, keyType: keyType, path: "\(path).\(key)")
                issues.append(contentsOf: validateScalarOrMessage(element, typeName: valueType, registry: registry, path: "\(path).\(key)", allowNull: false))
                return issues
            }
        case .optional, .required:
            return validateScalarOrMessage(value, typeName: field.typeName, registry: registry, path: path, allowNull: field.cardinality == .optional)
        }
    }

    private func validateScalarOrMessage(
        _ value: Any,
        typeName: String,
        registry: ProtobufRegistry,
        path: String,
        allowNull: Bool
    ) -> [ProtobufDiagnostic] {
        if value is NSNull {
            return allowNull ? [] : [ProtobufDiagnostic(message: "Null is not allowed at \(path).")]
        }

        if registry.snapshot.messagesByName[typeName] != nil {
            guard let object = value as? [String: Any] else {
                return [ProtobufDiagnostic(message: "Expected object for message at \(path).")]
            }
            return validateJSONObject(object, messageType: ProtobufTypeID(fullName: typeName), registry: registry, path: path)
        }

        if let enumDesc = registry.snapshot.enumsByName[typeName] {
            if let stringValue = value as? String {
                if enumDesc.values.contains(where: { $0.name == stringValue }) { return [] }
                return [ProtobufDiagnostic(message: "Unknown enum value '\(stringValue)' at \(path).")]
            }
            if let intValue = value as? Int {
                if enumDesc.values.contains(where: { $0.number == intValue }) { return [] }
                return [ProtobufDiagnostic(message: "Unknown enum number \(intValue) at \(path).")]
            }
            return [ProtobufDiagnostic(message: "Expected enum string or number at \(path).")]
        }

        switch typeName {
        case "string":
            return value is String ? [] : [ProtobufDiagnostic(message: "Expected string at \(path).")]
        case "bool":
            return value is Bool ? [] : [ProtobufDiagnostic(message: "Expected bool at \(path).")]
        case "bytes":
            return value is String ? [] : [ProtobufDiagnostic(message: "Expected base64-encoded string at \(path).")]
        case "double", "float":
            return (value is Double || value is Int) ? [] : [ProtobufDiagnostic(message: "Expected number at \(path).")]
        case "int32", "int64", "uint32", "uint64", "sint32", "sint64", "fixed32", "fixed64", "sfixed32", "sfixed64":
            if value is Int || value is Int64 || value is String { return [] }
            return [ProtobufDiagnostic(message: "Expected integer at \(path).")]
        default:
            return [ProtobufDiagnostic(message: "Unsupported field type '\(typeName)' at \(path).")]
        }
    }

    private func validateMapKey(_ key: String, keyType: String, path: String) -> [ProtobufDiagnostic] {
        switch keyType {
        case "string":
            return []
        case "int32", "int64", "uint32", "uint64":
            return Int(key) != nil ? [] : [ProtobufDiagnostic(message: "Invalid map key '\(key)' at \(path).")]
        case "bool":
            return (key == "true" || key == "false") ? [] : [ProtobufDiagnostic(message: "Invalid bool map key '\(key)' at \(path).")]
        default:
            return [ProtobufDiagnostic(message: "Unsupported map key type '\(keyType)'.")]
        }
    }

    // MARK: JSON encoding

    private func encodeMessage(
        _ object: [String: Any],
        messageType: ProtobufTypeID,
        registry: ProtobufRegistry,
        into writer: inout ProtobufWriter
    ) throws {
        guard let descriptor = registry.snapshot.messagesByName[messageType.fullName] else {
            throw RuntimeError.unknownMessage(messageType.fullName)
        }

        for field in descriptor.fields {
            guard let value = object[field.jsonName] else { continue }
            try encodeField(value, field: field, registry: registry, into: &writer)
        }
    }

    private func encodeField(
        _ value: Any,
        field: ProtoFieldDescriptor,
        registry: ProtobufRegistry,
        into writer: inout ProtobufWriter
    ) throws {
        if value is NSNull { return }

        switch field.cardinality {
        case .repeated:
            guard let array = value as? [Any] else {
                throw RuntimeError.typeMismatch("Expected array.", field: field.jsonName)
            }
            for element in array {
                try encodeSingularField(element, field: field, registry: registry, into: &writer)
            }
        case .map:
            guard let mapObject = value as? [String: Any] else {
                throw RuntimeError.typeMismatch("Expected object.", field: field.jsonName)
            }
            let (keyType, valueType) = parseMapTypes(field.typeName)
            for (key, element) in mapObject {
                var entryWriter = ProtobufWriter()
                try encodeMapEntry(key: key, keyType: keyType, value: element, valueType: valueType, registry: registry, into: &entryWriter)
                writer.writeEmbeddedMessage(fieldNumber: field.number, entryWriter.data)
            }
        case .optional, .required:
            try encodeSingularField(value, field: field, registry: registry, into: &writer)
        }
    }

    private func encodeMapEntry(
        key: String,
        keyType: String,
        value: Any,
        valueType: String,
        registry: ProtobufRegistry,
        into writer: inout ProtobufWriter
    ) throws {
        try encodeScalarOrMessage(value, typeName: valueType, fieldNumber: 2, registry: registry, into: &writer)

        switch keyType {
        case "string":
            writer.writeString(fieldNumber: 1, key)
        case "int32":
            guard let intKey = Int32(key) else { throw RuntimeError.encoding("Invalid int32 map key.") }
            writer.writeInt32(fieldNumber: 1, intKey)
        case "int64":
            guard let intKey = Int64(key) else { throw RuntimeError.encoding("Invalid int64 map key.") }
            writer.writeInt64(fieldNumber: 1, intKey)
        case "bool":
            writer.writeBool(fieldNumber: 1, key == "true")
        default:
            writer.writeString(fieldNumber: 1, key)
        }
    }

    private func encodeSingularField(
        _ value: Any,
        field: ProtoFieldDescriptor,
        registry: ProtobufRegistry,
        into writer: inout ProtobufWriter
    ) throws {
        try encodeScalarOrMessage(value, typeName: field.typeName, fieldNumber: field.number, registry: registry, into: &writer)
    }

    private func encodeScalarOrMessage(
        _ value: Any,
        typeName: String,
        fieldNumber: Int,
        registry: ProtobufRegistry,
        into writer: inout ProtobufWriter
    ) throws {
        if let messageDescriptor = registry.snapshot.messagesByName[typeName] {
            guard let object = value as? [String: Any] else {
                throw RuntimeError.typeMismatch("Expected object.", field: messageDescriptor.fullName)
            }
            var nestedWriter = ProtobufWriter()
            try encodeMessage(object, messageType: ProtobufTypeID(fullName: typeName), registry: registry, into: &nestedWriter)
            writer.writeEmbeddedMessage(fieldNumber: fieldNumber, nestedWriter.data)
            return
        }

        if let enumDesc = registry.snapshot.enumsByName[typeName] {
            let number: Int
            if let stringValue = value as? String {
                guard let match = enumDesc.values.first(where: { $0.name == stringValue }) else {
                    throw RuntimeError.typeMismatch("Unknown enum value.", field: stringValue)
                }
                number = match.number
            } else if let intValue = value as? Int {
                number = intValue
            } else {
                throw RuntimeError.typeMismatch("Expected enum.", field: typeName)
            }
            writer.writeInt32(fieldNumber: fieldNumber, Int32(number))
            return
        }

        switch typeName {
        case "string":
            guard let stringValue = value as? String else { throw RuntimeError.typeMismatch("Expected string.", field: "\(fieldNumber)") }
            writer.writeString(fieldNumber: fieldNumber, stringValue)
        case "bool":
            guard let boolValue = value as? Bool else { throw RuntimeError.typeMismatch("Expected bool.", field: "\(fieldNumber)") }
            writer.writeBool(fieldNumber: fieldNumber, boolValue)
        case "bytes":
            guard let base64 = value as? String, let decoded = Data(base64Encoded: base64) else {
                throw RuntimeError.typeMismatch("Expected base64 string.", field: "\(fieldNumber)")
            }
            writer.writeBytes(fieldNumber: fieldNumber, decoded)
        case "double":
            let doubleValue: Double
            if let d = value as? Double { doubleValue = d }
            else if let i = value as? Int { doubleValue = Double(i) }
            else { throw RuntimeError.typeMismatch("Expected number.", field: "\(fieldNumber)") }
            writer.writeDouble(fieldNumber: fieldNumber, doubleValue)
        case "float":
            let floatValue: Float
            if let f = value as? Float { floatValue = f }
            else if let d = value as? Double { floatValue = Float(d) }
            else if let i = value as? Int { floatValue = Float(i) }
            else { throw RuntimeError.typeMismatch("Expected number.", field: "\(fieldNumber)") }
            writer.writeFloat(fieldNumber: fieldNumber, floatValue)
        case "int32", "sint32", "sfixed32":
            let intValue = try parseInt32(value)
            writer.writeInt32(fieldNumber: fieldNumber, intValue)
        case "int64", "sint64", "sfixed64":
            let intValue = try parseInt64(value)
            writer.writeInt64(fieldNumber: fieldNumber, intValue)
        case "uint32", "fixed32":
            let intValue = try parseUInt32(value)
            writer.writeUInt32(fieldNumber: fieldNumber, intValue)
        case "uint64", "fixed64":
            let intValue = try parseUInt64(value)
            writer.writeVarintField(fieldNumber: fieldNumber, value: intValue)
        default:
            throw RuntimeError.encoding("Unsupported scalar type '\(typeName)'.")
        }
    }

    // MARK: JSON decoding

    private func decodeMessage(
        from reader: inout ProtobufReader,
        descriptor: ProtoMessageDescriptor,
        registry: ProtobufRegistry
    ) throws -> [String: Any] {
        var result: [String: Any] = [:]
        var repeatedAccumulators: [String: [Any]] = [:]
        var mapAccumulators: [String: [Data]] = [:]

        while !reader.isAtEnd {
            let (fieldNumber, wireType) = try reader.readTag()
            guard let field = descriptor.fields.first(where: { $0.number == fieldNumber }) else {
                try reader.skipField(wireType: wireType)
                continue
            }

            switch field.cardinality {
            case .map:
                let entryData = try reader.readLengthDelimited()
                var entryReader = ProtobufReader(data: entryData)
                mapAccumulators[field.jsonName, default: []].append(entryData)
                _ = entryReader
            case .repeated:
                let decoded = try decodeFieldValue(from: &reader, wireType: wireType, field: field, registry: registry)
                repeatedAccumulators[field.jsonName, default: []].append(decoded)
            case .optional, .required:
                let decoded = try decodeFieldValue(from: &reader, wireType: wireType, field: field, registry: registry)
                result[field.jsonName] = decoded
            }
        }

        for (jsonName, values) in repeatedAccumulators {
            result[jsonName] = values
        }

        for (jsonName, entries) in mapAccumulators {
            guard let field = descriptor.fields.first(where: { $0.jsonName == jsonName }) else { continue }
            let (_, valueType) = parseMapTypes(field.typeName)
            var mapObject: [String: Any] = [:]
            for entryData in entries {
                var entryReader = ProtobufReader(data: entryData)
                var key: String?
                var value: Any?
                while !entryReader.isAtEnd {
                    let (entryField, entryWire) = try entryReader.readTag()
                    if entryField == 1 {
                        key = try decodeMapKey(from: &entryReader, wireType: entryWire, mapType: field.typeName)
                    } else if entryField == 2 {
                        value = try decodeScalarOrMessage(from: &entryReader, wireType: entryWire, typeName: valueType, registry: registry)
                    } else {
                        try entryReader.skipField(wireType: entryWire)
                    }
                }
                if let key, let value {
                    mapObject[key] = value
                }
            }
            result[jsonName] = mapObject
        }

        return result
    }

    private func decodeFieldValue(
        from reader: inout ProtobufReader,
        wireType: Int,
        field: ProtoFieldDescriptor,
        registry: ProtobufRegistry
    ) throws -> Any {
        try decodeScalarOrMessage(from: &reader, wireType: wireType, typeName: field.typeName, registry: registry)
    }

    private func decodeScalarOrMessage(
        from reader: inout ProtobufReader,
        wireType: Int,
        typeName: String,
        registry: ProtobufRegistry
    ) throws -> Any {
        if registry.snapshot.messagesByName[typeName] != nil {
            let data = try reader.readLengthDelimited()
            var nestedReader = ProtobufReader(data: data)
            guard let descriptor = registry.snapshot.messagesByName[typeName] else {
                throw RuntimeError.unknownMessage(typeName)
            }
            return try decodeMessage(from: &nestedReader, descriptor: descriptor, registry: registry)
        }

        if registry.snapshot.enumsByName[typeName] != nil {
            let raw = Int(try reader.readVarint())
            if let enumDesc = registry.snapshot.enumsByName[typeName],
               let match = enumDesc.values.first(where: { $0.number == raw }) {
                return match.name
            }
            return raw
        }

        switch typeName {
        case "string":
            let data = try reader.readLengthDelimited()
            guard let string = String(data: data, encoding: .utf8) else { throw ProtobufWireError.invalidUTF8 }
            return string
        case "bytes":
            let data = try reader.readLengthDelimited()
            return data.base64EncodedString()
        case "bool":
            return try reader.readVarint() != 0
        case "double":
            guard wireType == ProtobufWireType.fixed64.rawValue else {
                return Double(Int(try reader.readVarint()))
            }
            let bits = try reader.readFixed64()
            return Double(bitPattern: bits)
        case "float":
            guard wireType == ProtobufWireType.fixed32.rawValue else {
                return Float(Int(try reader.readVarint()))
            }
            let bits = try reader.readFixed32()
            return Float(bitPattern: bits)
        case "int32", "sint32", "sfixed32":
            return Int(try reader.readVarint())
        case "int64", "sint64", "sfixed64":
            return Int64(bitPattern: try reader.readVarint())
        case "uint32", "fixed32":
            return UInt32(try reader.readVarint())
        case "uint64", "fixed64":
            return try reader.readVarint()
        default:
            try reader.skipField(wireType: wireType)
            return NSNull()
        }
    }

    private func decodeMapKey(from reader: inout ProtobufReader, wireType: Int, mapType: String) throws -> String {
        let keyType = parseMapTypes(mapType).0
        switch keyType {
        case "string":
            let data = try reader.readLengthDelimited()
            return String(data: data, encoding: .utf8) ?? ""
        case "int32", "int64", "uint32", "uint64":
            return String(Int(try reader.readVarint()))
        case "bool":
            return (try reader.readVarint() != 0) ? "true" : "false"
        default:
            let data = try reader.readLengthDelimited()
            return String(data: data, encoding: .utf8) ?? ""
        }
    }

    // MARK: Helpers

    private func parseMapTypes(_ typeName: String) -> (String, String) {
        guard typeName.hasPrefix("map<"), typeName.hasSuffix(">") else {
            return ("string", typeName)
        }
        let inner = String(typeName.dropFirst(4).dropLast())
        if let commaIndex = inner.firstIndex(of: ",") {
            let key = inner[..<commaIndex].trimmingCharacters(in: .whitespaces)
            let value = inner[inner.index(after: commaIndex)...].trimmingCharacters(in: .whitespaces)
            return (String(key), String(value))
        }
        return ("string", inner)
    }

    private func parseInt32(_ value: Any) throws -> Int32 {
        if let intValue = value as? Int { return Int32(intValue) }
        if let intValue = value as? Int32 { return intValue }
        if let stringValue = value as? String, let parsed = Int32(stringValue) { return parsed }
        throw RuntimeError.typeMismatch("Expected int32.", field: "value")
    }

    private func parseInt64(_ value: Any) throws -> Int64 {
        if let intValue = value as? Int { return Int64(intValue) }
        if let intValue = value as? Int64 { return intValue }
        if let stringValue = value as? String, let parsed = Int64(stringValue) { return parsed }
        throw RuntimeError.typeMismatch("Expected int64.", field: "value")
    }

    private func parseUInt32(_ value: Any) throws -> UInt32 {
        if let intValue = value as? Int, intValue >= 0 { return UInt32(intValue) }
        if let stringValue = value as? String, let parsed = UInt32(stringValue) { return parsed }
        throw RuntimeError.typeMismatch("Expected uint32.", field: "value")
    }

    private func parseUInt64(_ value: Any) throws -> UInt64 {
        if let intValue = value as? Int, intValue >= 0 { return UInt64(intValue) }
        if let stringValue = value as? String, let parsed = UInt64(stringValue) { return parsed }
        throw RuntimeError.typeMismatch("Expected uint64.", field: "value")
    }
}

private extension ProtobufWriter {
    mutating func writeVarintField(fieldNumber: Int, value: UInt64) {
        writeTag(fieldNumber: fieldNumber, wireType: ProtobufWireType.varint.rawValue)
        writeVarint(value)
    }
}
