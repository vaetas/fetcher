import Foundation

struct ProtocSchemaCompiler: ProtoSchemaCompiler, Sendable {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func compile(source: StagedProtoSource) async throws -> CompiledDescriptorSet {
        let protocURL = try locateProtoc()
        let outputURL = source.stagingRoot.appendingPathComponent("descriptor-set.pb")

        var arguments = [
            "--descriptor_set_out=\(outputURL.path)",
            "--include_imports",
            "--include_source_info"
        ]

        for importRoot in source.importRoots {
            arguments.append("-I")
            arguments.append(importRoot.path)
        }

        if let wellKnown = bundledWellKnownPath() {
            arguments.append("-I")
            arguments.append(wellKnown)
        }

        arguments.append(contentsOf: source.rootFiles.map(\.path))

        let process = Process()
        process.executableURL = protocURL
        process.arguments = arguments
        process.currentDirectoryURL = source.stagingRoot

        let stderrPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderrPipe

        try process.run()

        let finished = await withTaskCancellationHandler {
            await waitForProcess(process, timeout: SchemaResourceLimits.schemaRefreshTimeout)
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }

        if finished == .timedOut {
            if process.isRunning { process.terminate() }
            throw DefinitionRefreshError.compilationFailed("protoc timed out after \(Int(SchemaResourceLimits.schemaRefreshTimeout)) seconds.")
        }

        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
        let diagnostics = parseProtocDiagnostics(stderrText)

        guard process.terminationStatus == 0 else {
            let message = diagnostics.first?.message ?? stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
            throw DefinitionRefreshError.compilationFailed(message.isEmpty ? "protoc compilation failed." : message)
        }

        guard fileManager.fileExists(atPath: outputURL.path) else {
            throw DefinitionRefreshError.compilationFailed("protoc did not produce a descriptor set.")
        }

        let data = try Data(contentsOf: outputURL)
        if data.isEmpty {
            throw DefinitionRefreshError.compilationFailed("protoc produced an empty descriptor set.")
        }

        return CompiledDescriptorSet(data: data, diagnostics: diagnostics)
    }

    private enum WaitResult {
        case exited
        case timedOut
    }

    private func waitForProcess(_ process: Process, timeout: TimeInterval) async -> WaitResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let deadline = Date().addingTimeInterval(timeout)
                while process.isRunning, Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                if process.isRunning {
                    continuation.resume(returning: .timedOut)
                } else {
                    continuation.resume(returning: .exited)
                }
            }
        }
    }

    private func locateProtoc() throws -> URL {
        if let bundled = Bundle.main.url(forResource: "protoc", withExtension: nil) {
            return bundled
        }

        let helpersPath = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("Helpers/protoc")
        if fileManager.isExecutableFile(atPath: helpersPath.path) {
            return helpersPath
        }

        let devHelpers = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Helpers/protoc")
        if fileManager.isExecutableFile(atPath: devHelpers.path) {
            return devHelpers
        }

        let pathProtoc = URL(fileURLWithPath: "/usr/bin/which")
        let whichProcess = Process()
        whichProcess.executableURL = pathProtoc
        whichProcess.arguments = ["protoc"]
        let pipe = Pipe()
        whichProcess.standardOutput = pipe
        whichProcess.standardError = FileHandle.nullDevice
        try? whichProcess.run()
        whichProcess.waitUntilExit()
        if whichProcess.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty,
               fileManager.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        throw DefinitionRefreshError.compilationFailed("protoc was not found. Bundle protoc or install it on PATH for local .proto compilation.")
    }

    private func bundledWellKnownPath() -> String? {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("well-known", isDirectory: true),
            Bundle.main.resourceURL?.appendingPathComponent("include", isDirectory: true),
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("well-known", isDirectory: true)
        ]
        for candidate in candidates {
            if let candidate, fileManager.fileExists(atPath: candidate.path) {
                return candidate.path
            }
        }
        return nil
    }

    private func parseProtocDiagnostics(_ stderr: String) -> [EditorDiagnostic] {
        var diagnostics: [EditorDiagnostic] = []
        let lines = stderr.split(whereSeparator: \.isNewline)
        for line in lines {
            let text = String(line)
            guard !text.isEmpty else { continue }
            let severity: EditorDiagnostic.Severity = text.contains("error:") ? .error : .warning
            diagnostics.append(EditorDiagnostic(
                severity: severity,
                message: text,
                source: "protoc"
            ))
        }
        return diagnostics
    }
}
