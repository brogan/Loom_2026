"""
Sprite configuration models.

Sprites in Loom combine:
- A Shape2D (from shapes.xml)
- Location, size, rotation parameters
- Animation parameters
- A RendererSet reference (from rendering.xml)
"""
from dataclasses import dataclass, field
from copy import deepcopy
from typing import List, Optional


@dataclass
class MorphTargetRef:
    """A reference to a single morph target file in the morphTargets/ directory."""
    file: str = ""   # filename, e.g. "foo_mt_1.poly.xml" or "foo_mt_1.curve.xml"
    name: str = ""   # optional display name


# All supported easing types (must match Scala EasingType enum)
EASING_TYPES = [
    "LINEAR",
    "EASE_IN_QUAD", "EASE_OUT_QUAD", "EASE_IN_OUT_QUAD", "EASE_OUT_IN_QUAD",
    "EASE_IN_CUBIC", "EASE_OUT_CUBIC", "EASE_IN_OUT_CUBIC", "EASE_OUT_IN_CUBIC",
    "EASE_IN_QUART", "EASE_OUT_QUART", "EASE_IN_OUT_QUART", "EASE_OUT_IN_QUART",
    "EASE_IN_QUINT", "EASE_OUT_QUINT", "EASE_IN_OUT_QUINT", "EASE_OUT_IN_QUINT",
    "EASE_IN_SINE", "EASE_OUT_SINE", "EASE_IN_OUT_SINE", "EASE_OUT_IN_SINE",
    "EASE_IN_EXPO", "EASE_OUT_EXPO", "EASE_IN_OUT_EXPO", "EASE_OUT_IN_EXPO",
    "EASE_IN_CIRC", "EASE_OUT_CIRC", "EASE_IN_OUT_CIRC", "EASE_OUT_IN_CIRC",
    "EASE_IN_ELASTIC", "EASE_OUT_ELASTIC", "EASE_IN_OUT_ELASTIC", "EASE_OUT_IN_ELASTIC",
    "EASE_IN_BACK", "EASE_OUT_BACK", "EASE_IN_OUT_BACK", "EASE_OUT_IN_BACK",
    "EASE_IN_BOUNCE", "EASE_OUT_BOUNCE", "EASE_IN_OUT_BOUNCE", "EASE_OUT_IN_BOUNCE",
]

LOOP_MODES = ["NONE", "LOOP", "PING_PONG"]


@dataclass
class Vector2D:
    """2D vector for sprite parameters."""
    x: float = 0.0
    y: float = 0.0


@dataclass
class Keyframe:
    """A single animation keyframe defining sprite state at a specific draw cycle."""
    draw_cycle: int = 0
    pos_x: float = 0.0
    pos_y: float = 0.0
    scale_x: float = 1.0
    scale_y: float = 1.0
    rotation: float = 0.0
    easing: str = "LINEAR"
    morph_amount: float = 0.0

    def copy(self) -> 'Keyframe':
        return deepcopy(self)


@dataclass
class SpriteParams:
    """
    Parameters for a sprite instance.

    These control the sprite's position, size, rotation, and animation.
    """
    # Position (matches Scala SpriteDef.position)
    location_x: float = 0.0
    location_y: float = 0.0

    # Scale (matches Scala SpriteDef.scale)
    size_x: float = 1.0
    size_y: float = 1.0

    # Rotation angle (matches Scala SpriteDef.rotation)
    start_rotation: float = 0.0

    # Animation settings (matches Scala SpriteDef animation fields)
    animation_enabled: bool = True
    total_draws: int = 0  # 0 = infinite (draw forever), >0 = stop after N draw cycles
    scale_range_x_min: float = 0.0
    scale_range_x_max: float = 0.0
    scale_range_y_min: float = 0.0
    scale_range_y_max: float = 0.0
    rotation_range_min: float = 0.0
    rotation_range_max: float = 0.0
    translation_range_x_min: float = 0.0
    translation_range_x_max: float = 0.0
    translation_range_y_min: float = 0.0
    translation_range_y_max: float = 0.0

    # Editor-only fields (not in Scala model, preserved for editor use)
    rot_offset_x: float = 0.0
    rot_offset_y: float = 0.0
    scale_factor_x: float = 1.0
    scale_factor_y: float = 1.0
    rotation_factor: float = 0.0
    speed_factor_x: float = 0.0
    speed_factor_y: float = 0.0

    # Jitter mode: oscillate around home position instead of cumulative drift
    jitter: bool = False

    # Keyframe animation fields
    loop_mode: str = "NONE"
    keyframes: List[Keyframe] = field(default_factory=list)

    # Morph target fields (chain: base → mt1 → mt2 → …)
    morph_targets: List[MorphTargetRef] = field(default_factory=list)
    morph_min: float = 0.0
    morph_max: float = 1.0


@dataclass
class SpriteDef:
    """
    Definition of a single sprite.

    A sprite combines a shape with rendering and animation parameters.
    """
    name: str = "default"
    enabled: bool = True

    # Reference to shape (from shapes.xml)
    shape_set_name: str = ""
    shape_name: str = ""

    # Reference to renderer set (from rendering.xml)
    renderer_set_name: str = ""

    # Sprite parameters
    params: SpriteParams = field(default_factory=SpriteParams)

    # Animator type: "random" (jitter) or "keyframe" (interpolated keyframes)
    animator_type: str = "random"


@dataclass
class SpriteSet:
    """
    A named set of sprites.

    Allows grouping related sprites together.
    """
    name: str = "default"
    sprites: List[SpriteDef] = field(default_factory=list)

    def add(self, sprite: SpriteDef) -> None:
        """Add a sprite to this set."""
        self.sprites.append(sprite)

    def remove(self, index: int) -> None:
        """Remove a sprite by index."""
        if 0 <= index < len(self.sprites):
            self.sprites.pop(index)

    def get(self, name: str) -> Optional[SpriteDef]:
        """Get a sprite by name."""
        for sprite in self.sprites:
            if sprite.name == name:
                return sprite
        return None


@dataclass
class SpriteLibrary:
    """
    A library of sprite sets.

    Top-level container for sprite configuration.
    """
    name: str = "MainLibrary"
    sprite_sets: List[SpriteSet] = field(default_factory=list)

    def add(self, sprite_set: SpriteSet) -> None:
        """Add a sprite set to the library."""
        self.sprite_sets.append(sprite_set)

    def remove(self, index: int) -> None:
        """Remove a sprite set by index."""
        if 0 <= index < len(self.sprite_sets):
            self.sprite_sets.pop(index)

    def get(self, name: str) -> Optional[SpriteSet]:
        """Get a sprite set by name."""
        for sprite_set in self.sprite_sets:
            if sprite_set.name == name:
                return sprite_set
        return None

    def get_all_sprite_names(self) -> List[str]:
        """Get all sprite names across all sets."""
        names = []
        for sprite_set in self.sprite_sets:
            for sprite in sprite_set.sprites:
                names.append(f"{sprite_set.name}/{sprite.name}")
        return names
