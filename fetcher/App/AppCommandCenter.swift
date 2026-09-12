import Foundation
import Observation
import SwiftUI

enum AppCommandID: Hashable, Sendable {
    case sendRequest
    case cancelRequest
    case newRequest
    case newProject
    case duplicateRequest
    case toggleInspector
    case focusURL
    case formatJSON
}

@MainActor
@Observable
final class AppCommandCenter {
    var selectedProjectID: UUID? {
        didSet { persist() }
    }
    var selectedRequestID: UUID? {
        didSet { persist() }
    }
    var isInspectorPresented = false {
        didSet { UserDefaults.standard.set(isInspectorPresented, forKey: Keys.inspector) }
    }
    var searchText = ""
    var selectedRequestTab: RequestEditorTab = .params {
        didSet { UserDefaults.standard.set(selectedRequestTab.rawValue, forKey: Keys.requestTab) }
    }
    var selectedResponseTab: ResponseViewerTab = .body {
        didSet { UserDefaults.standard.set(selectedResponseTab.rawValue, forKey: Keys.responseTab) }
    }
    var requestResponseSplit: Double = 0.55 {
        didSet { UserDefaults.standard.set(requestResponseSplit, forKey: Keys.split) }
    }
    var expandedProjectIDs: Set<UUID> = [] {
        didSet {
            UserDefaults.standard.set(expandedProjectIDs.map(\.uuidString), forKey: Keys.expanded)
        }
    }

    weak var workspace: RequestWorkspaceModel?
    var onNewProject: (() -> Void)?
    var onNewRequest: (() -> Void)?
    var onDuplicateRequest: (() -> Void)?
    var focusURLToken = UUID()

    init() {
        restore()
    }

    func perform(_ command: AppCommandID) {
        switch command {
        case .sendRequest:
            workspace?.send()
        case .cancelRequest:
            workspace?.cancel()
        case .newRequest:
            onNewRequest?()
        case .newProject:
            onNewProject?()
        case .duplicateRequest:
            onDuplicateRequest?()
        case .toggleInspector:
            isInspectorPresented.toggle()
        case .focusURL:
            focusURLToken = UUID()
        case .formatJSON:
            workspace?.formatJSONBody()
        }
    }

    private func persist() {
        UserDefaults.standard.set(selectedProjectID?.uuidString, forKey: Keys.project)
        UserDefaults.standard.set(selectedRequestID?.uuidString, forKey: Keys.request)
    }

    private func restore() {
        if let project = UserDefaults.standard.string(forKey: Keys.project) {
            selectedProjectID = UUID(uuidString: project)
        }
        if let request = UserDefaults.standard.string(forKey: Keys.request) {
            selectedRequestID = UUID(uuidString: request)
        }
        isInspectorPresented = UserDefaults.standard.bool(forKey: Keys.inspector)
        if let tab = UserDefaults.standard.string(forKey: Keys.requestTab),
           let value = RequestEditorTab(rawValue: tab) {
            selectedRequestTab = value
        }
        if let tab = UserDefaults.standard.string(forKey: Keys.responseTab),
           let value = ResponseViewerTab(rawValue: tab) {
            selectedResponseTab = value
        }
        let split = UserDefaults.standard.double(forKey: Keys.split)
        if split > 0 {
            requestResponseSplit = split
        }
        if let expanded = UserDefaults.standard.stringArray(forKey: Keys.expanded) {
            expandedProjectIDs = Set(expanded.compactMap(UUID.init(uuidString:)))
        }
    }

    private enum Keys {
        static let project = "fetcher.selectedProjectID"
        static let request = "fetcher.selectedRequestID"
        static let inspector = "fetcher.inspectorPresented"
        static let requestTab = "fetcher.requestTab"
        static let responseTab = "fetcher.responseTab"
        static let split = "fetcher.requestResponseSplit"
        static let expanded = "fetcher.expandedProjects"
    }
}

enum RequestEditorTab: String, CaseIterable, Identifiable, Sendable {
    case params
    case auth
    case headers
    case body
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .params: "Params"
        case .auth: "Auth"
        case .headers: "Headers"
        case .body: "Body"
        case .settings: "Settings"
        }
    }
}

enum ResponseViewerTab: String, CaseIterable, Identifiable, Sendable {
    case body
    case headers
    case cookies
    case timing
    case raw

    var id: String { rawValue }

    var title: String {
        switch self {
        case .body: "Body"
        case .headers: "Headers"
        case .cookies: "Cookies"
        case .timing: "Timing"
        case .raw: "Raw"
        }
    }
}
