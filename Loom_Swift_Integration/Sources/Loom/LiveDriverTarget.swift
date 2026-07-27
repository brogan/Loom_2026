import Foundation
import LoomEngine

/// Which part of a staged sprite instance a driver field lives in — the
/// sprite's own 9 `TransformDrivers` fields, a driver nested inside a
/// specific pass of the assigned transform (subdivision) set, or a driver
/// on a specific renderer in the assigned renderer set.
enum LiveDriverSection: String, Hashable, CaseIterable, Codable {
    case sprite, subdivision, curveRefinement, extension_, convolution, evolution, segmentExtraction, dissolution, renderer

    /// Display heading for the navigator's section grouping.
    var sectionLabel: String {
        switch self {
        case .sprite:            return "Sprite"
        case .subdivision:       return "Transform — Subdivision"
        case .curveRefinement:   return "Transform — Curve Refinement"
        case .extension_:        return "Transform — Extension"
        case .convolution:       return "Transform — Convolution"
        case .evolution:         return "Transform — Evolution"
        case .segmentExtraction: return "Transform — Segment Extraction"
        case .dissolution:       return "Transform — Dissolution"
        case .renderer:          return "Renderer"
        }
    }
}

/// Identifies one addressable driver field anywhere in a staged sprite
/// instance, by **name** rather than array position — `entryName` is the
/// pass/renderer's own `name` field (empty/unused for `.sprite`, which has
/// only one instance of itself). Name, not index, is the stable identity
/// here: transform passes live in individually ordered, individually
/// editable per-kind stacks, so inserting/removing/reordering a pass shifts
/// every position-based reference after it (see `SessionWorkflow.md` §3.2).
///
/// Names aren't guaranteed unique, though — a pass can be left blank, or
/// share a name with a sibling. `recordedIndex` is the pass's array position
/// *at the time this target was discovered*, kept only as a tiebreaker: name
/// resolution (`doubleKeyPath(in:)` and friends) matches by name first, and
/// only consults `recordedIndex` when that match is ambiguous or empty.
/// Hashable so it can key dictionaries and drive SwiftUI selection.
struct LiveDriverTarget: Hashable, Codable {
    let section: LiveDriverSection
    let entryName: String
    let field: String
    let recordedIndex: Int
}

// MARK: - Keypath resolution
//
// Each method below is the ONE place enumerating every real driver field
// this app can address — the engine side is fully generic over whatever
// `WritableKeyPath` these produce (`LoomEngine.setDriverEnabled`/
// `updateDoubleDriverRateRange`/etc.), so adding a new addressable field
// later only means adding a case here, not new engine code. Resolution is
// instance-aware (not a stateless computed property) because it has to
// look up which array index currently holds `entryName` before a keypath
// can be built at all — that lookup can only be answered against a live
// instance, and can change between calls if the sprite's assigned transform
// or renderer set has since been swapped out from under it.

extension LiveDriverTarget {
    /// Resolves `entryName` to a current array index, preferring an
    /// unambiguous name match; falls back to `recordedIndex` (if it's still
    /// among the ambiguous matches) or the first match otherwise. `nil` when
    /// the name no longer exists at all (e.g. the pass was deleted).
    private func resolveIndex(count: Int, nameAt: (Int) -> String) -> Int? {
        guard count > 0 else { return nil }
        let matches = (0..<count).filter { nameAt($0) == entryName }
        if matches.count == 1 { return matches[0] }
        if matches.isEmpty { return nil }
        return matches.contains(recordedIndex) ? recordedIndex : matches.first
    }

    func doubleKeyPath(in instance: SpriteInstance) -> WritableKeyPath<SpriteInstance, DoubleDriver>? {
        switch section {
        case .sprite:
            switch field {
            case "rotation": return \.def.animation.drivers!.rotation
            case "morph":    return \.def.animation.drivers!.morph
            case "opacity":  return \.def.animation.drivers!.opacity
            case "shape":    return \.def.animation.drivers!.shape
            default: return nil
            }

        case .subdivision:
            guard let idx = resolveIndex(count: instance.subdivisionParams.count,
                                         nameAt: { instance.subdivisionParams[$0].name }) else { return nil }
            switch field {
            case "lineRatio":      return \.subdivisionParams[idx].drivers!.lineRatio
            case "cpRatio":        return \.subdivisionParams[idx].drivers!.cpRatio
            case "cpNormalOffset": return \.subdivisionParams[idx].drivers!.cpNormalOffset
            case "insetScale":     return \.subdivisionParams[idx].drivers!.insetScale
            case "insetRotation":  return \.subdivisionParams[idx].drivers!.insetRotation
            case "ranDiv":         return \.subdivisionParams[idx].drivers!.ranDiv
            case "ptwTranslateX":  return \.subdivisionParams[idx].drivers!.ptwTranslateX
            case "ptwTranslateY":  return \.subdivisionParams[idx].drivers!.ptwTranslateY
            case "ptwScale":       return \.subdivisionParams[idx].drivers!.ptwScale
            case "ptwRotation":    return \.subdivisionParams[idx].drivers!.ptwRotation
            default: return nil
            }

        case .curveRefinement:
            guard let idx = resolveIndex(count: instance.curveRefinementParams.count,
                                         nameAt: { instance.curveRefinementParams[$0].name }) else { return nil }
            switch field {
            case "displacement":   return \.curveRefinementParams[idx].drivers!.displacement
            case "cpNormalOffset": return \.curveRefinementParams[idx].drivers!.cpNormalOffset
            default: return nil
            }

        case .extension_:
            guard let idx = resolveIndex(count: instance.extensionParams.count,
                                         nameAt: { instance.extensionParams[$0].name }) else { return nil }
            switch field {
            case "branchAngle":       return \.extensionParams[idx].branchAngle
            case "branchLineLength":  return \.extensionParams[idx].branchLineLength
            case "extrusionDistance": return \.extensionParams[idx].extrusionDistance
            case "structurePhase":    return \.extensionParams[idx].structurePhase
            default: return nil
            }

        case .convolution:
            guard let idx = resolveIndex(count: instance.convolutionParams.count,
                                         nameAt: { instance.convolutionParams[$0].name }) else { return nil }
            switch field {
            case "twistAmount":            return \.convolutionParams[idx].twistAmount
            case "shearAmount":             return \.convolutionParams[idx].shearAmount
            case "bendCurvature":           return \.convolutionParams[idx].bendCurvature
            case "displacementStrength":    return \.convolutionParams[idx].displacementStrength
            case "displacementScrollRate":  return \.convolutionParams[idx].displacementScrollRate
            default: return nil
            }

        case .evolution:
            guard let idx = resolveIndex(count: instance.evolutionParams.count,
                                         nameAt: { instance.evolutionParams[$0].name }) else { return nil }
            switch field {
            case "convergencePressure": return \.evolutionParams[idx].convergencePressure
            case "generationPhase":     return \.evolutionParams[idx].generationPhase
            default: return nil
            }

        case .segmentExtraction:
            guard let idx = resolveIndex(count: instance.segmentExtractionParams.count,
                                         nameAt: { instance.segmentExtractionParams[$0].name }) else { return nil }
            return field == "driver" ? \.segmentExtractionParams[idx].driver : nil

        case .dissolution:
            guard let idx = resolveIndex(count: instance.dissolutionParams.count,
                                         nameAt: { instance.dissolutionParams[$0].name }) else { return nil }
            return field == "dissolutionPhase" ? \.dissolutionParams[idx].dissolutionPhase : nil

        case .renderer:
            guard let idx = resolveIndex(count: instance.rendererSet.renderers.count,
                                         nameAt: { instance.rendererSet.renderers[$0].name }) else { return nil }
            switch field {
            case "strokeWidth":    return \.rendererSet.renderers[idx].drivers!.strokeWidth
            case "opacity":        return \.rendererSet.renderers[idx].drivers!.opacity
            case "blur":           return \.rendererSet.renderers[idx].drivers!.blur
            case "pointSize":      return \.rendererSet.renderers[idx].drivers!.pointSize
            case "gradientBlend":  return \.rendererSet.renderers[idx].drivers!.gradientBlend
            default: return nil
            }
        }
    }

    func vectorKeyPath(in instance: SpriteInstance) -> WritableKeyPath<SpriteInstance, VectorDriver>? {
        switch (section, field) {
        case (.sprite, "position"): return \.def.animation.drivers!.position
        case (.sprite, "scale"):    return \.def.animation.drivers!.scale
        default: return nil
        }
    }

    func colorKeyPath(in instance: SpriteInstance) -> WritableKeyPath<SpriteInstance, ColorDriver>? {
        guard section == .renderer else { return nil }
        guard let idx = resolveIndex(count: instance.rendererSet.renderers.count,
                                     nameAt: { instance.rendererSet.renderers[$0].name }) else { return nil }
        switch field {
        case "fillColor":   return \.rendererSet.renderers[idx].drivers!.fillColor!
        case "strokeColor": return \.rendererSet.renderers[idx].drivers!.strokeColor!
        default: return nil
        }
    }

    /// Sprite-only: `subdivisionSet`/`rendererSet`/`cycleName` are
    /// `NameDriver`-backed overrides with an enabled toggle but no rate/range
    /// concept (they select a set name, not a continuous value).
    func nameKeyPath(in instance: SpriteInstance) -> WritableKeyPath<SpriteInstance, NameDriver>? {
        switch (section, field) {
        case (.sprite, "subdivisionSet"): return \.def.animation.drivers!.subdivisionSet
        case (.sprite, "rendererSet"):    return \.def.animation.drivers!.rendererSet
        case (.sprite, "cycleName"):      return \.def.animation.drivers!.cycleName
        default: return nil
        }
    }
}

// MARK: - Discovery

/// One driver field found configured on a resolved staged instance, ready
/// to populate `LiveSessionController.StagedSprite`.
struct LiveDriverDiscovery {
    let target: LiveDriverTarget
    let label: String
    let enabled: Bool
    /// `nil` for name-drivers (subdivisionSet/rendererSet/cycleName), which
    /// have no rate/range concept — only the enabled toggle applies to them.
    let controlInfo: LiveSessionController.DriverControlInfo?
}

enum LiveDriverDiscoverer {
    /// Finds every driver field this sprite's own authoring (or its
    /// assigned transform/renderer sets) actually configured — enabled, or
    /// set to a non-constant mode — mirroring the same "only show what's
    /// relevant" filtering the sprite-only version of this feature already
    /// used, now extended across transform-set passes and renderer entries.
    static func discover(in instance: SpriteInstance) -> [LiveDriverDiscovery] {
        var out: [LiveDriverDiscovery] = []

        func isConfigured(_ d: DoubleDriver) -> Bool { d.enabled || d.mode != .constant }
        func isConfigured(_ d: VectorDriver) -> Bool { d.enabled || d.mode != .constant }
        func isConfigured(_ d: ColorDriver) -> Bool { d.enabled || d.mode != .constant }

        func addDouble(_ section: LiveDriverSection, _ entryName: String, _ recordedIndex: Int, _ field: String, _ label: String, _ d: DoubleDriver) {
            guard isConfigured(d) else { return }
            out.append(LiveDriverDiscovery(
                target: LiveDriverTarget(section: section, entryName: entryName, field: field, recordedIndex: recordedIndex),
                label: label, enabled: d.enabled,
                controlInfo: LiveSessionController.DriverControlInfo.make(from: d)
            ))
        }
        func addVector(_ section: LiveDriverSection, _ entryName: String, _ recordedIndex: Int, _ field: String, _ label: String, _ d: VectorDriver) {
            guard isConfigured(d) else { return }
            out.append(LiveDriverDiscovery(
                target: LiveDriverTarget(section: section, entryName: entryName, field: field, recordedIndex: recordedIndex),
                label: label, enabled: d.enabled,
                controlInfo: LiveSessionController.DriverControlInfo.make(from: d)
            ))
        }
        func addColor(_ section: LiveDriverSection, _ entryName: String, _ recordedIndex: Int, _ field: String, _ label: String, _ d: ColorDriver) {
            guard isConfigured(d) else { return }
            out.append(LiveDriverDiscovery(
                target: LiveDriverTarget(section: section, entryName: entryName, field: field, recordedIndex: recordedIndex),
                label: label, enabled: d.enabled,
                controlInfo: LiveSessionController.DriverControlInfo.make(from: d)
            ))
        }
        func addName(_ section: LiveDriverSection, _ entryName: String, _ recordedIndex: Int, _ field: String, _ label: String, _ d: NameDriver) {
            guard d != .disabled else { return }
            out.append(LiveDriverDiscovery(
                target: LiveDriverTarget(section: section, entryName: entryName, field: field, recordedIndex: recordedIndex),
                label: label, enabled: d.enabled, controlInfo: nil
            ))
        }

        // Sprite
        let td = instance.def.animation.drivers ?? .identity
        addDouble(.sprite, "", 0, "rotation", "Rotation", td.rotation)
        addDouble(.sprite, "", 0, "morph", "Morph", td.morph)
        addDouble(.sprite, "", 0, "opacity", "Opacity", td.opacity)
        addDouble(.sprite, "", 0, "shape", "Shape", td.shape)
        addVector(.sprite, "", 0, "position", "Position", td.position)
        addVector(.sprite, "", 0, "scale", "Scale", td.scale)
        addName(.sprite, "", 0, "subdivisionSet", "Subdivision Set", td.subdivisionSet)
        addName(.sprite, "", 0, "rendererSet", "Renderer Set", td.rendererSet)
        addName(.sprite, "", 0, "cycleName", "Cycle Name", td.cycleName)

        // Transform set: subdivision passes (nested optional drivers)
        for (i, pass) in instance.subdivisionParams.enumerated() {
            guard let d = pass.drivers else { continue }
            let p = pass.name.isEmpty ? "Subdivision #\(i + 1)" : pass.name
            addDouble(.subdivision, pass.name, i, "lineRatio", "\(p) — Line Ratio", d.lineRatio)
            addDouble(.subdivision, pass.name, i, "cpRatio", "\(p) — CP Ratio", d.cpRatio)
            addDouble(.subdivision, pass.name, i, "cpNormalOffset", "\(p) — CP Normal Offset", d.cpNormalOffset)
            addDouble(.subdivision, pass.name, i, "insetScale", "\(p) — Inset Scale", d.insetScale)
            addDouble(.subdivision, pass.name, i, "insetRotation", "\(p) — Inset Rotation", d.insetRotation)
            addDouble(.subdivision, pass.name, i, "ranDiv", "\(p) — Random Divergence", d.ranDiv)
            addDouble(.subdivision, pass.name, i, "ptwTranslateX", "\(p) — PTW Translate X", d.ptwTranslateX)
            addDouble(.subdivision, pass.name, i, "ptwTranslateY", "\(p) — PTW Translate Y", d.ptwTranslateY)
            addDouble(.subdivision, pass.name, i, "ptwScale", "\(p) — PTW Scale", d.ptwScale)
            addDouble(.subdivision, pass.name, i, "ptwRotation", "\(p) — PTW Rotation", d.ptwRotation)
        }

        // Transform set: curve refinement passes (nested optional drivers)
        for (i, pass) in instance.curveRefinementParams.enumerated() {
            guard let d = pass.drivers else { continue }
            let p = pass.name.isEmpty ? "Curve Refinement #\(i + 1)" : pass.name
            addDouble(.curveRefinement, pass.name, i, "displacement", "\(p) — Displacement", d.displacement)
            addDouble(.curveRefinement, pass.name, i, "cpNormalOffset", "\(p) — CP Normal Offset", d.cpNormalOffset)
        }

        // Transform set: extension passes (direct fields)
        for (i, pass) in instance.extensionParams.enumerated() {
            let p = pass.name.isEmpty ? "Extension #\(i + 1)" : pass.name
            addDouble(.extension_, pass.name, i, "branchAngle", "\(p) — Branch Angle", pass.branchAngle)
            addDouble(.extension_, pass.name, i, "branchLineLength", "\(p) — Branch Line Length", pass.branchLineLength)
            addDouble(.extension_, pass.name, i, "extrusionDistance", "\(p) — Extrusion Distance", pass.extrusionDistance)
            addDouble(.extension_, pass.name, i, "structurePhase", "\(p) — Structure Phase", pass.structurePhase)
        }

        // Transform set: convolution passes (direct fields)
        for (i, pass) in instance.convolutionParams.enumerated() {
            let p = pass.name.isEmpty ? "Convolution #\(i + 1)" : pass.name
            addDouble(.convolution, pass.name, i, "twistAmount", "\(p) — Twist Amount", pass.twistAmount)
            addDouble(.convolution, pass.name, i, "shearAmount", "\(p) — Shear Amount", pass.shearAmount)
            addDouble(.convolution, pass.name, i, "bendCurvature", "\(p) — Bend Curvature", pass.bendCurvature)
            addDouble(.convolution, pass.name, i, "displacementStrength", "\(p) — Displacement Strength", pass.displacementStrength)
            addDouble(.convolution, pass.name, i, "displacementScrollRate", "\(p) — Displacement Scroll Rate", pass.displacementScrollRate)
        }

        // Transform set: evolution passes (direct fields)
        for (i, pass) in instance.evolutionParams.enumerated() {
            let p = pass.name.isEmpty ? "Evolution #\(i + 1)" : pass.name
            addDouble(.evolution, pass.name, i, "convergencePressure", "\(p) — Convergence Pressure", pass.convergencePressure)
            addDouble(.evolution, pass.name, i, "generationPhase", "\(p) — Generation Phase", pass.generationPhase)
        }

        // Transform set: segment extraction passes (direct field)
        for (i, pass) in instance.segmentExtractionParams.enumerated() {
            let p = pass.name.isEmpty ? "Segment Extraction #\(i + 1)" : pass.name
            addDouble(.segmentExtraction, pass.name, i, "driver", "\(p)", pass.driver)
        }

        // Transform set: dissolution passes (direct field)
        for (i, pass) in instance.dissolutionParams.enumerated() {
            let p = pass.name.isEmpty ? "Dissolution #\(i + 1)" : pass.name
            addDouble(.dissolution, pass.name, i, "dissolutionPhase", "\(p) — Dissolution Phase", pass.dissolutionPhase)
        }

        // Renderer set entries (nested optional drivers)
        for (i, renderer) in instance.rendererSet.renderers.enumerated() {
            guard let d = renderer.drivers else { continue }
            let r = renderer.name.isEmpty ? "Renderer #\(i + 1)" : renderer.name
            addDouble(.renderer, renderer.name, i, "strokeWidth", "\(r) — Stroke Width", d.strokeWidth)
            addDouble(.renderer, renderer.name, i, "opacity", "\(r) — Opacity", d.opacity)
            addDouble(.renderer, renderer.name, i, "blur", "\(r) — Blur", d.blur)
            addDouble(.renderer, renderer.name, i, "pointSize", "\(r) — Point Size", d.pointSize)
            addDouble(.renderer, renderer.name, i, "gradientBlend", "\(r) — Gradient Blend", d.gradientBlend)
            if let fc = d.fillColor { addColor(.renderer, renderer.name, i, "fillColor", "\(r) — Fill Color", fc) }
            if let sc = d.strokeColor { addColor(.renderer, renderer.name, i, "strokeColor", "\(r) — Stroke Color", sc) }
        }

        return out
    }
}
