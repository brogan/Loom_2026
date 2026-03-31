"""
Data models for rendering configuration.
These classes represent the structure that will be serialized to/from XML.
"""
from dataclasses import dataclass, field
from typing import List, Optional
from .constants import (
    RenderMode, ChangeKind, Motion, Cycle, Scale, ColorChannel, PlaybackMode,
    BrushDrawMode, PostCompletionMode
)


@dataclass
class Color:
    """RGBA color representation."""
    r: int = 0
    g: int = 0
    b: int = 0
    a: int = 255

    def copy(self) -> 'Color':
        return Color(self.r, self.g, self.b, self.a)

    def to_tuple(self) -> tuple:
        return (self.r, self.g, self.b, self.a)

    @classmethod
    def from_tuple(cls, t: tuple) -> 'Color':
        return cls(t[0], t[1], t[2], t[3] if len(t) > 3 else 255)

    def __eq__(self, other):
        if not isinstance(other, Color):
            return False
        return self.r == other.r and self.g == other.g and self.b == other.b and self.a == other.a


@dataclass
class SizeChange:
    """Configuration for stroke width or point size animation."""
    enabled: bool = False
    kind: ChangeKind = ChangeKind.SEQ
    motion: Motion = Motion.UP
    cycle: Cycle = Cycle.CONSTANT
    scale: Scale = Scale.POLY
    min_val: float = 0.0
    max_val: float = 1.0
    increment: float = 0.1
    pause_max: int = 0
    size_palette: List[float] = field(default_factory=list)

    def copy(self) -> 'SizeChange':
        return SizeChange(
            enabled=self.enabled,
            kind=self.kind,
            motion=self.motion,
            cycle=self.cycle,
            scale=self.scale,
            min_val=self.min_val,
            max_val=self.max_val,
            increment=self.increment,
            pause_max=self.pause_max,
            size_palette=list(self.size_palette)
        )


@dataclass
class ColorChange:
    """Configuration for stroke color animation."""
    enabled: bool = False
    kind: ChangeKind = ChangeKind.SEQ
    motion: Motion = Motion.UP
    cycle: Cycle = Cycle.CONSTANT
    scale: Scale = Scale.POLY
    min_color: Color = field(default_factory=Color)
    max_color: Color = field(default_factory=lambda: Color(255, 255, 255, 255))
    increment: Color = field(default_factory=lambda: Color(1, 1, 1, 1))
    pause_max: int = 0
    palette: List[Color] = field(default_factory=list)
    pause_channel: ColorChannel = ColorChannel.GREEN
    pause_color_min: Color = field(default_factory=Color)
    pause_color_max: Color = field(default_factory=Color)

    def copy(self) -> 'ColorChange':
        return ColorChange(
            enabled=self.enabled,
            kind=self.kind,
            motion=self.motion,
            cycle=self.cycle,
            scale=self.scale,
            min_color=self.min_color.copy(),
            max_color=self.max_color.copy(),
            increment=self.increment.copy(),
            pause_max=self.pause_max,
            palette=[c.copy() for c in self.palette],
            pause_channel=self.pause_channel,
            pause_color_min=self.pause_color_min.copy(),
            pause_color_max=self.pause_color_max.copy()
        )


@dataclass
class FillColorChange(ColorChange):
    """Configuration for fill color animation. Uses a dedicated Scala method for dispatch."""

    def copy(self) -> 'FillColorChange':
        return FillColorChange(
            enabled=self.enabled,
            kind=self.kind,
            motion=self.motion,
            cycle=self.cycle,
            scale=self.scale,
            min_color=self.min_color.copy(),
            max_color=self.max_color.copy(),
            increment=self.increment.copy(),
            pause_max=self.pause_max,
            palette=[c.copy() for c in self.palette],
            pause_channel=self.pause_channel,
            pause_color_min=self.pause_color_min.copy(),
            pause_color_max=self.pause_color_max.copy()
        )


@dataclass
class MeanderConfig:
    """Configuration for meandering-path perturbation of brush strokes."""
    enabled: bool = False
    amplitude: float = 8.0
    frequency: float = 0.03
    samples: int = 24
    seed: int = 0
    animated: bool = False
    anim_speed: float = 0.01
    scale_along_path: bool = False
    scale_along_path_frequency: float = 0.05
    scale_along_path_range: float = 0.4

    def copy(self) -> 'MeanderConfig':
        return MeanderConfig(
            enabled=self.enabled,
            amplitude=self.amplitude,
            frequency=self.frequency,
            samples=self.samples,
            seed=self.seed,
            animated=self.animated,
            anim_speed=self.anim_speed,
            scale_along_path=self.scale_along_path,
            scale_along_path_frequency=self.scale_along_path_frequency,
            scale_along_path_range=self.scale_along_path_range,
        )


@dataclass
class BrushConfig:
    """Configuration for brush-based rendering (BRUSHED mode)."""
    brush_names: List[str] = field(default_factory=list)
    brush_enabled: List[bool] = field(default_factory=list)
    draw_mode: BrushDrawMode = BrushDrawMode.FULL_PATH
    stamp_spacing: float = 4.0
    spacing_easing: str = "LINEAR"
    follow_tangent: bool = True
    perpendicular_jitter_min: float = -2.0
    perpendicular_jitter_max: float = 2.0
    scale_min: float = 0.8
    scale_max: float = 1.2
    opacity_min: float = 0.6
    opacity_max: float = 1.0
    stamps_per_frame: int = 10
    agent_count: int = 1
    post_completion_mode: PostCompletionMode = PostCompletionMode.HOLD
    blur_radius: int = 0
    meander_config: MeanderConfig = field(default_factory=MeanderConfig)
    pressure_size_influence: float = 0.0
    pressure_alpha_influence: float = 0.0

    def copy(self) -> 'BrushConfig':
        return BrushConfig(
            brush_names=list(self.brush_names),
            brush_enabled=list(self.brush_enabled),
            draw_mode=self.draw_mode,
            stamp_spacing=self.stamp_spacing,
            spacing_easing=self.spacing_easing,
            follow_tangent=self.follow_tangent,
            perpendicular_jitter_min=self.perpendicular_jitter_min,
            perpendicular_jitter_max=self.perpendicular_jitter_max,
            scale_min=self.scale_min,
            scale_max=self.scale_max,
            opacity_min=self.opacity_min,
            opacity_max=self.opacity_max,
            stamps_per_frame=self.stamps_per_frame,
            agent_count=self.agent_count,
            post_completion_mode=self.post_completion_mode,
            blur_radius=self.blur_radius,
            meander_config=self.meander_config.copy(),
            pressure_size_influence=self.pressure_size_influence,
            pressure_alpha_influence=self.pressure_alpha_influence,
        )


@dataclass
class StencilConfig:
    """Configuration for stencil-based rendering (STAMPED mode).
    Stamps full-RGBA PNGs; no tinting. Opacity animated via opacity_change."""
    stencil_names: List[str] = field(default_factory=list)
    stencil_enabled: List[bool] = field(default_factory=list)
    draw_mode: BrushDrawMode = BrushDrawMode.FULL_PATH
    stamp_spacing: float = 4.0
    spacing_easing: str = "LINEAR"
    follow_tangent: bool = True
    perpendicular_jitter_min: float = -2.0
    perpendicular_jitter_max: float = 2.0
    scale_min: float = 0.8
    scale_max: float = 1.2
    stamps_per_frame: int = 10
    agent_count: int = 1
    post_completion_mode: PostCompletionMode = PostCompletionMode.HOLD
    opacity_change: SizeChange = field(default_factory=SizeChange)

    def copy(self) -> 'StencilConfig':
        return StencilConfig(
            stencil_names=list(self.stencil_names),
            stencil_enabled=list(self.stencil_enabled),
            draw_mode=self.draw_mode,
            stamp_spacing=self.stamp_spacing,
            spacing_easing=self.spacing_easing,
            follow_tangent=self.follow_tangent,
            perpendicular_jitter_min=self.perpendicular_jitter_min,
            perpendicular_jitter_max=self.perpendicular_jitter_max,
            scale_min=self.scale_min,
            scale_max=self.scale_max,
            stamps_per_frame=self.stamps_per_frame,
            agent_count=self.agent_count,
            post_completion_mode=self.post_completion_mode,
            opacity_change=self.opacity_change.copy()
        )


@dataclass
class Renderer:
    """A single renderer configuration."""
    name: str
    enabled: bool = True
    mode: RenderMode = RenderMode.FILLED
    stroke_width: float = 1.0
    stroke_color: Color = field(default_factory=Color)
    fill_color: Color = field(default_factory=Color)
    point_size: float = 2.0
    hold_length: int = 1
    point_stroked: bool = True
    point_filled: bool = True
    stroke_width_change: SizeChange = field(default_factory=SizeChange)
    stroke_color_change: ColorChange = field(default_factory=ColorChange)
    fill_color_change: FillColorChange = field(default_factory=FillColorChange)
    point_size_change: SizeChange = field(default_factory=SizeChange)
    brush_config: Optional[BrushConfig] = None
    stencil_config: Optional[StencilConfig] = None

    def copy(self) -> 'Renderer':
        return Renderer(
            name=self.name,
            enabled=self.enabled,
            mode=self.mode,
            stroke_width=self.stroke_width,
            stroke_color=self.stroke_color.copy(),
            fill_color=self.fill_color.copy(),
            point_size=self.point_size,
            hold_length=self.hold_length,
            point_stroked=self.point_stroked,
            point_filled=self.point_filled,
            stroke_width_change=self.stroke_width_change.copy(),
            stroke_color_change=self.stroke_color_change.copy(),
            fill_color_change=self.fill_color_change.copy(),
            point_size_change=self.point_size_change.copy(),
            brush_config=self.brush_config.copy() if self.brush_config else None,
            stencil_config=self.stencil_config.copy() if self.stencil_config else None
        )

    def has_any_changes(self) -> bool:
        """Returns True if any change is enabled."""
        return (self.stroke_width_change.enabled or
                self.stroke_color_change.enabled or
                self.fill_color_change.enabled or
                self.point_size_change.enabled)


@dataclass
class RendererSet:
    """A set of renderers with playback configuration."""
    name: str
    renderers: List[Renderer] = field(default_factory=list)
    playback_mode: PlaybackMode = PlaybackMode.SEQUENTIAL
    preferred_renderer: str = ""
    preferred_probability: float = 50.0
    modify_internal_parameters: bool = False

    def add_renderer(self, renderer: Renderer) -> None:
        self.renderers.append(renderer)

    def remove_renderer(self, name: str) -> bool:
        for i, r in enumerate(self.renderers):
            if r.name == name:
                del self.renderers[i]
                return True
        return False

    def get_renderer(self, name: str) -> Optional[Renderer]:
        for r in self.renderers:
            if r.name == name:
                return r
        return None

    def get_renderer_names(self) -> List[str]:
        return [r.name for r in self.renderers]

    def move_renderer(self, from_index: int, to_index: int) -> None:
        if 0 <= from_index < len(self.renderers) and 0 <= to_index < len(self.renderers):
            renderer = self.renderers.pop(from_index)
            self.renderers.insert(to_index, renderer)

    def copy(self) -> 'RendererSet':
        return RendererSet(
            name=self.name,
            renderers=[r.copy() for r in self.renderers],
            playback_mode=self.playback_mode,
            preferred_renderer=self.preferred_renderer,
            preferred_probability=self.preferred_probability,
            modify_internal_parameters=self.modify_internal_parameters
        )


@dataclass
class RendererSetLibrary:
    """A library containing multiple renderer sets."""
    name: str
    renderer_sets: List[RendererSet] = field(default_factory=list)

    def add_renderer_set(self, renderer_set: RendererSet) -> None:
        self.renderer_sets.append(renderer_set)

    def remove_renderer_set(self, name: str) -> bool:
        for i, rs in enumerate(self.renderer_sets):
            if rs.name == name:
                del self.renderer_sets[i]
                return True
        return False

    def get_renderer_set(self, name: str) -> Optional[RendererSet]:
        for rs in self.renderer_sets:
            if rs.name == name:
                return rs
        return None

    def get_renderer_set_names(self) -> List[str]:
        return [rs.name for rs in self.renderer_sets]

    def move_renderer_set(self, from_index: int, to_index: int) -> None:
        if 0 <= from_index < len(self.renderer_sets) and 0 <= to_index < len(self.renderer_sets):
            rs = self.renderer_sets.pop(from_index)
            self.renderer_sets.insert(to_index, rs)

    def copy(self) -> 'RendererSetLibrary':
        return RendererSetLibrary(
            name=self.name,
            renderer_sets=[rs.copy() for rs in self.renderer_sets]
        )
