import Foundation

enum SchemaSourceReaderError: Error, Sendable, Equatable {
    case pathNotFound(String)
    case symlinkRejected(String)
    case traversalRejected(String)
    case limitExceeded(String)
    case unreadable(String)
}

struct SchemaSourceReader: Sendable {
    private let fileManager: FileManager
    private let skippedDirectoryNames: Set<String>
    private let allowedExtensions: Set<String>

    init(
        fileManager: FileManager = .default,
        skippedDirectoryNames: Set<String> = [".git", ".svn", ".hg", "node_modules", "DerivedData", ".build"],
        allowedExtensions: Set<String> = ["proto"]
    ) {
        self.fileManager = fileManager
        self.skippedDirectoryNames = skippedDirectoryNames
        self.allowedExtensions = allowedExtensions
    }

    func stageProtoSources(
        from roots: [URL],
        importRoots: [URL],
        into stagingRoot: URL
    ) throws -> StagedProtoSource {
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)

        var stagedRootFiles: [URL] = []
        var stagedImportRoots = Set<URL>()

        for root in roots {
            let destination = stagingRoot.appendingPathComponent("roots", isDirectory: true)
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            let staged = try copyProtoTree(from: root, into: destination, depth: 0)
            stagedRootFiles.append(contentsOf: staged)
        }

        for importRoot in importRoots {
            let destination = stagingRoot.appendingPathComponent("imports/\(importRoot.lastPathComponent)", isDirectory: true)
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            _ = try copyProtoTree(from: importRoot, into: destination, depth: 0)
            stagedImportRoots.insert(destination)
        }

        return StagedProtoSource(
            rootFiles: stagedRootFiles.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending },
            importRoots: Array(stagedImportRoots).sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending },
            stagingRoot: stagingRoot
        )
    }

    func readLimitedData(from url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        if values.isSymbolicLink == true {
            throw SchemaSourceReaderError.symlinkRejected(url.path)
        }
        if let size = values.fileSize, size > SchemaResourceLimits.maxIndividualFileBytes {
            throw SchemaSourceReaderError.limitExceeded("File '\(url.lastPathComponent)' exceeds size limit.")
        }
        let data = try Data(contentsOf: url)
        if data.count > SchemaResourceLimits.maxIndividualFileBytes {
            throw SchemaSourceReaderError.limitExceeded("File '\(url.lastPathComponent)' exceeds size limit.")
        }
        return data
    }

    private func copyProtoTree(from source: URL, into destinationRoot: URL, depth: Int) throws -> [URL] {
        if depth > SchemaResourceLimits.maxNestingDepth {
            throw SchemaSourceReaderError.limitExceeded("Source nesting exceeds depth limit.")
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory) else {
            throw SchemaSourceReaderError.pathNotFound(source.path)
        }

        let linkValues = try source.resourceValues(forKeys: [.isSymbolicLinkKey])
        if linkValues.isSymbolicLink == true {
            throw SchemaSourceReaderError.symlinkRejected(source.path)
        }

        if isDirectory.boolValue {
            return try enumerateProtoFiles(in: source, destinationRoot: destinationRoot, depth: depth)
        }

        guard allowedExtensions.contains(source.pathExtension.lowercased()) else {
            return []
        }

        let relativeName = source.lastPathComponent
        let destination = destinationRoot.appendingPathComponent(relativeName)
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try readLimitedData(from: source)
        try data.write(to: destination, options: .atomic)
        return [destination]
    }

    private func enumerateProtoFiles(
        in directory: URL,
        destinationRoot: URL,
        depth: Int
    ) throws -> [URL] {
        var results: [URL] = []
        var fileCount = 0

        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw SchemaSourceReaderError.unreadable(directory.path)
        }

        let basePath = directory.standardizedFileURL.path

        for case let itemURL as URL in enumerator {
            fileCount += 1
            if fileCount > SchemaResourceLimits.maxFileCount {
                throw SchemaSourceReaderError.limitExceeded("Source directory exceeds file count limit.")
            }

            let values = try itemURL.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
            if values.isSymbolicLink == true {
                throw SchemaSourceReaderError.symlinkRejected(itemURL.path)
            }

            if values.isDirectory == true {
                if skippedDirectoryNames.contains(itemURL.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard values.isRegularFile == true else { continue }

            let standardized = itemURL.standardizedFileURL.path
            guard standardized.hasPrefix(basePath + "/") || standardized == basePath else {
                throw SchemaSourceReaderError.traversalRejected(itemURL.path)
            }

            let ext = itemURL.pathExtension.lowercased()
            guard allowedExtensions.contains(ext) else { continue }

            let relativePath = String(standardized.dropFirst(basePath.count + 1))
            let destination = destinationRoot.appendingPathComponent(relativePath)
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try readLimitedData(from: itemURL)
            try data.write(to: destination, options: .atomic)
            results.append(destination)
        }

        return results
    }
}
