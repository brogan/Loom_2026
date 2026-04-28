# Data Models

All models live in `loom_parameter_editor/models/`. Every model is a Python `dataclass`. All models implement a `copy()` method returning a deep-enough copy to avoid sharing mutable state between the UI and saved data.

---

## `models/project.py`

```python
@dataclass
class ProjectFile:
    domain : str  # lookup key: global, rendering, polygons, subdivision, shapes, sprites, curves, points, ovals
    path   : str  # relative path from project directory

@dataclass
class Project:
    name        : str           = "New Project"
    description : str           = ""
    created     : datetime      = field(default_factory=datetime.now)
    modified    : datetime      = field(default_factory=datetime.now)
    files       : List[ProjectFile] = field(default_factory=list)
    version     : str           = "1.0"
```

---

## `models/global_config.py`

```python
@dataclass
class GlobalConfig:
    name                : str   = "Untitled"
    note                : str   = ""
    width               : int   = 1080
    height              : int   = 1080
    quality_multiple    : int   = 1
    scale_image         : bool  = False
    animating           : bool  = False
    draw_background_once: bool  = True
    subdividing         : bool  = True
    fullscreen          : bool  = False
    border_color        : Color = Color(0, 0, 0, 255)
    background_color    : Color = Color(255, 255, 255, 255)
    overlay_color       : Color = Color(0, 0, 0, 170)
    background_image_path: str  = ""
    three_d             : bool  = False
    camera_view_angle   : int   = 120
    serial              : bool  = False
    port                : str   = "/dev/ttyUSB0"
    mode                : str   = "bytes"
    quantity            : int   = 4
```

---

## `models/constants.py`

All enums here must stay synchronised with Scala constants in `org.loom.scene.Renderer`.

```python
class RenderMode(Enum):
    POINTS = 0 | STROKED = 1 | FILLED = 2 | FILLED_STROKED = 3 | BRUSHED = 4 | STAMPED = 5

class BrushDrawMode(Enum):
    FULL_PATH = 0 | PROGRESSIVE = 1

class PostCompletionMode(Enum):
    HOLD = 0 | LOOP = 1 | PING_PONG = 2

class ChangeKind(Enum):
    NUM_SEQ = 0 | NUM_RAN = 1 | SEQ = 2 | RAN = 3
    # Legacy aliases: PAL_SEQ → SEQ, PAL_RAN → RAN

class Motion(Enum):
    DOWN = -1 | PING_PONG = 0 | UP = 1

class Cycle(Enum):
    CONSTANT = 0 | ONCE = 1 | ONCE_REVERT = 2 | PAUSING = 3 | PAUSING_RANDOM = 4

class Scale(Enum):
    SPRITE = 0 | POLY = 1 | POINT = 2

class ColorChannel(Enum):
    RED = 0 | GREEN = 1 | BLUE = 2 | ALPHA = 3

class PlaybackMode(Enum):
    STATIC = 0 | SEQUENTIAL = 1 | RANDOM = 2 | ALL = 3
```

---

## `models/rendering.py`

```python
@dataclass
class Color:
    r : int = 0
    g : int = 0
    b : int = 0
    a : int = 255

@dataclass
class SizeChange:
    enabled    : bool      = False
    kind       : ChangeKind = ChangeKind.SEQ
    motion     : Motion    = Motion.UP
    cycle      : Cycle     = Cycle.CONSTANT
    scale      : Scale     = Scale.POLY
    min_val    : float     = 0.0
    max_val    : float     = 1.0
    increment  : float     = 0.1
    pause_max  : int       = 0
    size_palette: List[float] = []

@dataclass
class ColorChange:
    enabled         : bool          = False
    kind            : ChangeKind    = ChangeKind.SEQ
    motion          : Motion        = Motion.UP
    cycle           : Cycle         = Cycle.CONSTANT
    scale           : Scale         = Scale.POLY
    min_color       : Color         = Color()
    max_color       : Color         = Color(255,255,255,255)
    increment       : Color         = Color(1,1,1,1)
    pause_max       : int           = 0
    palette         : List[Color]   = []
    pause_channel   : ColorChannel  = ColorChannel.GREEN
    pause_color_min : Color         = Color()
    pause_color_max : Color         = Color()

class FillColorChange(ColorChange): ...  # same fields, different Scala dispatch

@dataclass
class MeanderConfig:
    enabled                    : bool  = False
    amplitude                  : float = 8.0
    frequency                  : float = 0.03
    samples                    : int   = 24
    seed                       : int   = 0
    animated                   : bool  = False
    anim_speed                 : float = 0.01
    scale_along_path           : bool  = False
    scale_along_path_frequency : float = 0.05
    scale_along_path_range     : float = 0.4

@dataclass
class BrushConfig:
    brush_names              : List[str]          = []
    brush_enabled            : List[bool]         = []
    draw_mode                : BrushDrawMode      = BrushDrawMode.FULL_PATH
    stamp_spacing            : float              = 4.0
    spacing_easing           : str               = "LINEAR"
    follow_tangent           : bool              = True
    perpendicular_jitter_min : float             = -2.0
    perpendicular_jitter_max : float             = 2.0
    scale_min                : float             = 0.8
    scale_max                : float             = 1.2
    opacity_min              : float             = 0.6
    opacity_max              : float             = 1.0
    stamps_per_frame         : int               = 10
    agent_count              : int               = 1
    post_completion_mode     : PostCompletionMode = PostCompletionMode.HOLD
    blur_radius              : int               = 0
    meander_config           : MeanderConfig     = MeanderConfig()
    pressure_size_influence  : float             = 0.0
    pressure_alpha_influence : float             = 0.0

@dataclass
class StencilConfig:
    stencil_names            : List[str]          = []
    stencil_enabled          : List[bool]         = []
    draw_mode                : BrushDrawMode      = BrushDrawMode.FULL_PATH
    stamp_spacing            : float              = 4.0
    spacing_easing           : str               = "LINEAR"
    follow_tangent           : bool              = True
    perpendicular_jitter_min : float             = -2.0
    perpendicular_jitter_max : float             = 2.0
    scale_min                : float             = 0.8
    scale_max                : float             = 1.2
    stamps_per_frame         : int               = 10
    agent_count              : int               = 1
    post_completion_mode     : PostCompletionMode = PostCompletionMode.HOLD
    opacity_change           : SizeChange        = SizeChange()

@dataclass
class Renderer:
    name                : str                    = "default"
    enabled             : bool                   = True
    mode                : RenderMode             = RenderMode.FILLED
    stroke_width        : float                  = 1.0
    stroke_color        : Color                  = Color()
    fill_color          : Color                  = Color()
    point_size          : float                  = 2.0
    hold_length         : int                    = 1
    point_stroked       : bool                   = True
    point_filled        : bool                   = True
    stroke_width_change : SizeChange             = SizeChange()
    stroke_color_change : ColorChange            = ColorChange()
    fill_color_change   : FillColorChange        = FillColorChange()
    point_size_change   : SizeChange             = SizeChange()
    brush_config        : Optional[BrushConfig]  = None
    stencil_config      : Optional[StencilConfig]= None

@dataclass
class RendererSet:
    name             : str          = "default"
    enabled          : bool         = True
    playback_mode    : PlaybackMode = PlaybackMode.STATIC
    change_frequency : int          = 1
    renderers        : List[Renderer] = []

@dataclass
class RendererSetLibrary:
    name          : str             = "MainLibrary"
    renderer_sets : List[RendererSet] = []
```

---

## `models/subdivision_config.py`

```python
class SubdivisionType(Enum):
    QUAD=0 | QUAD_BORD=1 | QUAD_BORD_ECHO=2 | QUAD_BORD_DOUBLE=3 | QUAD_BORD_DOUBLE_ECHO=4
    TRI=5 | TRI_BORD_A=6 | TRI_BORD_A_ECHO=7 | TRI_BORD_B=8 | TRI_STAR=9
    TRI_BORD_C=10 | TRI_BORD_C_ECHO=11
    SPLIT_VERT=12 | SPLIT_HORIZ=13 | SPLIT_DIAG=14
    ECHO=16 | ECHO_ABS_CENTER=17 | TRI_BORD_B_ECHO=18 | TRI_STAR_FILL=19

class VisibilityRule(Enum):
    ALL=0 | QUADS=1 | TRIS=2 | ALL_BUT_LAST=3
    ALTERNATE_ODD=4 | ALTERNATE_EVEN=5 | FIRST_HALF=6 | SECOND_HALF=7
    EVERY_THIRD=8 | EVERY_FOURTH=9 | EVERY_FIFTH=10
    RANDOM_1_2=11 | RANDOM_1_3=12 | RANDOM_1_5=13 | RANDOM_1_7=14 | RANDOM_1_10=15

@dataclass
class Vector2D:
    x : float = 0.0
    y : float = 0.0

@dataclass
class Range:
    min_val : float = 0.0
    max_val : float = 0.0

@dataclass
class RangeXY:
    x : Range = Range()
    y : Range = Range()

@dataclass
class Transform2D:
    translation : Vector2D = Vector2D()
    scale       : Vector2D = Vector2D(1.0, 1.0)
    rotation    : Vector2D = Vector2D()

@dataclass
class SubdivisionParams:
    name                         : str              = "default"
    enabled                      : bool             = True
    subdivision_type             : SubdivisionType  = SubdivisionType.QUAD
    visibility_rule              : VisibilityRule   = VisibilityRule.ALL
    ran_middle                   : bool             = False
    ran_div                      : float            = 100.0
    line_ratios                  : Vector2D         = Vector2D(0.5, 0.5)
    control_point_ratios         : Vector2D         = Vector2D(0.25, 0.75)
    inset_transform              : Transform2D      = Transform2D(scale=Vector2D(0.5, 0.5))
    continuous                   : bool             = True
    polys_transform              : bool             = True
    polys_transform_whole        : bool             = False
    ptw_probability              : float            = 100.0
    ptw_random_translation       : bool             = False
    ptw_random_scale             : bool             = False
    ptw_random_rotation          : bool             = False
    ptw_common_centre            : bool             = False
    ptw_random_centre_divisor    : float            = 100.0
    ptw_transform                : Transform2D      = Transform2D()
    ptw_random_translation_range : RangeXY          = RangeXY()
    ptw_random_scale_range       : RangeXY          = RangeXY(Range(1,1), Range(1,1))
    ptw_random_rotation_range    : Range            = Range()
    polys_transform_points       : bool             = False
    ptp_probability              : float            = 100.0
    transform_set                : TransformSetConfig = TransformSetConfig()

@dataclass
class SubdivisionParamsSet:
    name        : str                   = "default"
    params_list : List[SubdivisionParams] = []

@dataclass
class SubdivisionParamsSetCollection:
    params_sets : List[SubdivisionParamsSet] = []
```

---

## `models/transform_config.py`

```python
@dataclass
class Range:
    min_val : float = 0.0
    max_val : float = 0.0

@dataclass
class ExteriorAnchorsConfig:
    name  : str   = "ExteriorAnchors"
    range : Range = Range()

@dataclass
class CentralAnchorsConfig:
    name  : str   = "CentralAnchors"
    range : Range = Range()

@dataclass
class AnchorsLinkedToCentreConfig:
    name  : str   = "AnchorsLinkedToCentre"
    range : Range = Range()

@dataclass
class OuterControlPointsConfig:
    name  : str   = "OuterControlPoints"
    range : Range = Range()

@dataclass
class InnerControlPointsConfig:
    name  : str   = "InnerControlPoints"
    range : Range = Range()

@dataclass
class TransformSetConfig:
    transforms : List[Union[ExteriorAnchorsConfig, CentralAnchorsConfig,
                            AnchorsLinkedToCentreConfig, OuterControlPointsConfig,
                            InnerControlPointsConfig]] = []
```

---

## `models/sprite_config.py`

```python
class GeoSourceType(Enum):
    POLYGON_SET=0 | REGULAR_POLYGON=1 | INLINE_POINTS=2
    OPEN_CURVE_SET=3 | POINT_SET=4 | OVAL_SET=5

class GeoShape3DType(Enum):
    NONE=0 | CRYSTAL=1 | RECT_PRISM=2 | EXTRUSION=3 | GRID_PLANE=4 | GRID_BLOCK=5

EASING_TYPES : List[str]  # 41 easing function names
LOOP_MODES   : List[str]  # ["NONE", "LOOP", "PING_PONG"]

@dataclass
class GeoInlinePoint:
    x : float = 0.0
    y : float = 0.0

@dataclass
class MorphTargetRef:
    file : str = ""
    name : str = ""

@dataclass
class Keyframe:
    draw_cycle   : int   = 0
    pos_x        : float = 0.0
    pos_y        : float = 0.0
    scale_x      : float = 1.0
    scale_y      : float = 1.0
    rotation     : float = 0.0
    easing       : str   = "LINEAR"
    morph_amount : float = 0.0

@dataclass
class SpriteParams:
    location_x              : float = 0.0
    location_y              : float = 0.0
    size_x                  : float = 1.0
    size_y                  : float = 1.0
    start_rotation          : float = 0.0
    animation_enabled       : bool  = True
    total_draws             : int   = 0
    scale_range_x_min/max   : float = 0.0
    scale_range_y_min/max   : float = 0.0
    rotation_range_min/max  : float = 0.0
    translation_range_x_min/max : float = 0.0
    translation_range_y_min/max : float = 0.0
    rot_offset_x/y          : float = 0.0    # editor-only
    scale_factor_x/y        : float = 1.0    # editor-only
    rotation_factor         : float = 0.0    # editor-only
    speed_factor_x/y        : float = 0.0    # editor-only
    jitter                  : bool  = False
    loop_mode               : str   = "NONE"
    keyframes               : List[Keyframe] = []
    morph_targets           : List[MorphTargetRef] = []
    morph_min               : float = 0.0
    morph_max               : float = 1.0

@dataclass
class SpriteDef:
    name                          : str           = "default"
    enabled                       : bool          = True
    geo_source_type               : GeoSourceType = GeoSourceType.POLYGON_SET
    geo_polygon_set_name          : str           = ""
    geo_open_curve_set_name       : str           = ""
    geo_point_set_name            : str           = ""
    geo_oval_set_name             : str           = ""
    geo_regular_polygon_sides     : int           = 4
    geo_inline_points             : List[GeoInlinePoint] = []
    geo_subdivision_params_set_name : str         = ""
    geo_shape_3d_type             : GeoShape3DType = GeoShape3DType.NONE
    geo_shape_3d_param1/2/3       : int           = 4
    shape_set_name                : str           = ""  # auto-derived
    shape_name                    : str           = ""  # auto-derived
    renderer_set_name             : str           = ""
    animator_type                 : str           = "random"
    params                        : SpriteParams  = SpriteParams()

@dataclass
class SpriteSet:
    name    : str            = "default"
    sprites : List[SpriteDef] = []

@dataclass
class SpriteLibrary:
    name        : str           = "MainLibrary"
    sprite_sets : List[SpriteSet] = []
```

---

## Polygon / Curve / Point / Oval Models

These models follow the same `Library → Set → Entry` pattern.

```python
# models/polygon_config.py
class PolygonSet:
    name     : str
    file     : str   # filename in polygonSets/
    enabled  : bool

class PolygonSetLibrary:
    name         : str
    polygon_sets : List[PolygonSet]

# models/open_curve_config.py
class OpenCurveSet:
    name    : str
    file    : str   # filename in curveSets/
    enabled : bool

class OpenCurveSetLibrary:
    name       : str
    curve_sets : List[OpenCurveSet]

# models/point_config.py
class Point2D:
    x : float
    y : float

class PointSet:
    name    : str
    file    : str   # filename in pointSets/, empty for inline
    enabled : bool
    points  : List[Point2D]

class PointSetLibrary:
    name       : str
    point_sets : List[PointSet]

# models/oval_config.py
class OvalSet:
    name     : str
    enabled  : bool
    width    : float
    height   : float
    segments : int

class OvalSetLibrary:
    name      : str
    oval_sets : List[OvalSet]
```
