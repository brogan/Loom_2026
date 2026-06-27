import SwiftUI
import LoomEngine

// Wrapper shown in the main panel when a cycle is selected.
// Owns selectedStateIndex so the preview and list stay in sync.
struct CyclesMainView: View {
    @EnvironmentObject private var controller: AppController
    let cycle: SpriteCycle
    @State private var selectedStateIndex: Int? = nil

    var body: some View {
        CyclePreviewPanel(cycle: cycle, selectedStateIndex: $selectedStateIndex)
            .environmentObject(controller)
    }
}

struct CyclesTabView: View {

    @EnvironmentObject private var controller: AppController

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            cycleList
            Spacer(minLength: 0)
        }
        .sheet(isPresented: $controller.showingCycleEditor) {
            SpriteCycleEditorView()
                .environmentObject(controller)
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 6) {
            Text("Cycles")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button { controller.addCycle() } label: {
                Image(systemName: "plus").font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help("Add cycle")
            .modifier(LoomHoverHelp("Add cycle"))

            Button {
                if let idx = controller.selectedCycleIndex {
                    controller.removeCycle(at: idx)
                }
            } label: {
                Image(systemName: "minus").font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .disabled(controller.selectedCycleIndex == nil)
            .help("Remove selected cycle")
            .modifier(LoomHoverHelp("Remove selected cycle"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: List

    private var cycleList: some View {
        let cycles = controller.projectConfig?.cycles ?? []
        return List(selection: Binding(
            get: { controller.selectedCycleIndex },
            set: { controller.selectedCycleIndex = $0 }
        )) {
            ForEach(Array(cycles.enumerated()), id: \.offset) { idx, cycle in
                cycleRow(cycle: cycle, index: idx)
                    .tag(idx)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowSeparator(.hidden)
            }
            .onMove { source, dest in
                controller.moveCycle(from: source, to: dest)
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 30)
    }

    private func cycleRow(cycle: SpriteCycle, index: Int) -> some View {
        let isSelected = controller.selectedCycleIndex == index
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(cycle.name.isEmpty ? "Cycle" : cycle.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Text("\(cycle.states.count) states · \(cycle.totalCycleFrames) frames")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            Text(cycle.loopMode.displayName)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Button {
                controller.selectedCycleIndex = index
                controller.showingCycleEditor = true
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Edit cycle")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { controller.selectedCycleIndex = index }
    }
}
