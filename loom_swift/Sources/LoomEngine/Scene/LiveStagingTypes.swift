import Foundation

/// The `TransformDrivers` fields a Live-tab session can toggle on/off for a
/// staged sprite instance — see `LoomEngine.setDriverEnabled`.
public enum LiveDriverKey: String, CaseIterable, Sendable {
    case position, scale, rotation, morph, opacity, shape
    case subdivisionSet, rendererSet, cycleName
}

/// Errors raised by `LoomEngine`'s live-staging mutators
/// (`showSprite`/`updatePose`/`updateRendererSet`/`updateSubdivisionSet`/
/// `setDriverEnabled`) — see `LoomLiveV1Scope.md` §2.1.
public enum LiveStagingError: Error, LocalizedError, Sendable {
    case spriteNotFound(spriteSet: String, sprite: String)
    case instanceNotFound(String)
    case rendererSetNotFound(String)
    case subdivisionSetNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .spriteNotFound(let spriteSet, let sprite):
            return "Sprite '\(sprite)' not found in sprite set '\(spriteSet)'."
        case .instanceNotFound(let name):
            return "No staged instance named '\(name)'."
        case .rendererSetNotFound(let name):
            return "Renderer set '\(name)' not found."
        case .subdivisionSetNotFound(let name):
            return "Transform set '\(name)' not found."
        }
    }
}
