import Foundation

// MARK: - BrushProgressiveState

/// Persistent stamp cursor state for `BrushDrawMode.progressive`.
///
/// The perturbed paths are cached when the state is created so progressive
/// drawing follows one stable path across frames, even when meander animation
/// would otherwise change the path shape each render.
struct BrushProgressiveState {
    struct Agent {
        var edgeStartIndex: Int
        var edgeEndIndex: Int
        var currentEdgeIndex: Int
        var currentT: Double
        var completed: Bool
        var direction: Int
    }

    var edges: [BrushEdge]
    var paths: [PerturbedPath]
    var agents: [Agent]

    init(
        edges: [BrushEdge],
        agentCount: Int,
        config: BrushConfig,
        elapsedFrames: Double
    ) {
        self.edges = edges
        self.paths = edges.enumerated().map { index, edge in
            PathPerturbation.perturb(
                edge: edge,
                config: config.meander,
                edgeIndex: index,
                elapsedFrames: elapsedFrames,
                scaleMin: config.scaleMin,
                scaleMax: config.scaleMax
            )
        }

        let count = edges.count
        guard count > 0 else {
            self.agents = []
            return
        }

        let activeAgentCount = min(max(1, agentCount), count)
        self.agents = (0..<activeAgentCount).compactMap { index in
            let start = (index * count) / activeAgentCount
            let end = ((index + 1) * count) / activeAgentCount - 1
            guard start <= end else { return nil }
            return Agent(
                edgeStartIndex: start,
                edgeEndIndex: end,
                currentEdgeIndex: start,
                currentT: 0.0,
                completed: false,
                direction: 1
            )
        }
    }

    mutating func checkCompletion(mode: PostCompletionMode) {
        guard !agents.isEmpty,
              agents.allSatisfy(\.completed)
        else { return }

        switch mode {
        case .hold:
            break
        case .loop:
            for index in agents.indices {
                agents[index].completed = false
                agents[index].direction = 1
                agents[index].currentEdgeIndex = agents[index].edgeStartIndex
                agents[index].currentT = 0.0
            }
        case .pingPong:
            for index in agents.indices {
                agents[index].completed = false
                agents[index].direction *= -1
                if agents[index].direction > 0 {
                    agents[index].currentEdgeIndex = agents[index].edgeStartIndex
                    agents[index].currentT = 0.0
                } else {
                    agents[index].currentEdgeIndex = agents[index].edgeEndIndex
                    agents[index].currentT = 1.0
                }
            }
        }
    }
}
