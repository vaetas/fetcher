import SwiftUI

struct DefinitionDiagnosticsView: View {
    let diagnostics: [EditorDiagnostic]

    var body: some View {
        if diagnostics.isEmpty {
            EmptyStateView(
                title: "No Diagnostics",
                message: "Schema refresh did not report warnings or errors."
            )
        } else {
            EditorDiagnosticsList(diagnostics: diagnostics)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
