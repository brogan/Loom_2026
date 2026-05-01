import SwiftUI
import LoomEngine

struct SubdivisionTabView: View {

    @EnvironmentObject private var controller: AppController

    var body: some View {
        VStack(spacing: 0) {
            subdivisionList
            Divider()
            addButton
        }
    }

    @ViewBuilder
    private var subdivisionList: some View {
        let sets = controller.projectConfig?.subdivisionConfig.paramsSets ?? []
        if sets.isEmpty {
            emptyState(controller.projectConfig == nil ? "No project open" : "No subdivision sets")
        } else {
            List(selection: $controller.selectedSubdivisionIndex) {
                ForEach(Array(sets.enumerated()), id: \.offset) { idx, set in
                    SubdivisionSetRow(set: set)
                        .tag(idx)
                }
            }
            .listStyle(.plain)
        }
    }

    private var addButton: some View {
        HStack {
            Button {
                // Phase 3: create new subdivision set
            } label: {
                Label("New Subdivision Set", systemImage: "plus")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .padding(8)
            Spacer()
        }
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .foregroundStyle(.tertiary)
            .font(.caption)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SubdivisionSetRow: View {
    let set: SubdivisionParamsSet

    var body: some View {
        HStack(spacing: 6) {
            Text(set.name.isEmpty ? "(unnamed)" : set.name)
                .font(.system(size: 12))
                .lineLimit(1)
            Spacer()
            Text("\(set.params.count)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
