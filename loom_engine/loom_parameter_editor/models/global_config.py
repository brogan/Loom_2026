"""
Data model for global project configuration.
Matches the Scala GlobalConfig case class.
"""
from dataclasses import dataclass, field
from .rendering import Color


@dataclass
class GlobalConfig:
    """Global project configuration settings."""

    # Project identification
    name: str = "Untitled"
    note: str = ""

    # Canvas dimensions
    width: int = 1080
    height: int = 1080

    # Quality and rendering
    quality_multiple: int = 1
    scale_image: bool = False

    # Animation
    animating: bool = False
    draw_background_once: bool = True

    # Display
    fullscreen: bool = False
    border_color: Color = field(default_factory=lambda: Color(0, 0, 0, 255))
    background_color: Color = field(default_factory=lambda: Color(255, 255, 255, 255))
    overlay_color: Color = field(default_factory=lambda: Color(0, 0, 0, 170))

    # 3D settings
    three_d: bool = False
    camera_view_angle: int = 120

    # Subdivision
    subdividing: bool = True

    # Background image (alternative to background colour)
    background_image_path: str = ""

    # Serial communication (legacy)
    serial: bool = False
    port: str = "/dev/ttyUSB0"
    mode: str = "bytes"
    quantity: int = 4

    def copy(self) -> 'GlobalConfig':
        """Create a deep copy of this configuration."""
        return GlobalConfig(
            name=self.name,
            note=self.note,
            width=self.width,
            height=self.height,
            quality_multiple=self.quality_multiple,
            scale_image=self.scale_image,
            animating=self.animating,
            draw_background_once=self.draw_background_once,
            fullscreen=self.fullscreen,
            border_color=self.border_color.copy(),
            background_color=self.background_color.copy(),
            overlay_color=self.overlay_color.copy(),
            background_image_path=self.background_image_path,
            three_d=self.three_d,
            camera_view_angle=self.camera_view_angle,
            subdividing=self.subdividing,
            serial=self.serial,
            port=self.port,
            mode=self.mode,
            quantity=self.quantity
        )

    @classmethod
    def default(cls) -> 'GlobalConfig':
        """Create default configuration."""
        return cls()
