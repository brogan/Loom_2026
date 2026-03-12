"""
Enum definitions matching Scala Renderer constants.
These values must stay synchronized with org.loom.scene.Renderer.
"""
from enum import Enum


class RenderMode(Enum):
    """Renderer drawing mode - matches Renderer.POINTS, STROKED, FILLED, FILLED_STROKED, BRUSHED"""
    POINTS = 0
    STROKED = 1
    FILLED = 2
    FILLED_STROKED = 3
    BRUSHED = 4

    @classmethod
    def from_string(cls, s: str) -> 'RenderMode':
        return cls[s.upper()]

    def to_xml_string(self) -> str:
        return self.name


class BrushDrawMode(Enum):
    """Brush drawing mode - full path or progressive reveal"""
    FULL_PATH = 0
    PROGRESSIVE = 1

    @classmethod
    def from_string(cls, s: str) -> 'BrushDrawMode':
        return cls[s.upper()]

    def to_xml_string(self) -> str:
        return self.name


class PostCompletionMode(Enum):
    """Post-completion mode for progressive brush reveal"""
    HOLD = 0
    LOOP = 1
    PING_PONG = 2

    @classmethod
    def from_string(cls, s: str) -> 'PostCompletionMode':
        return cls[s.upper()]

    def to_xml_string(self) -> str:
        return self.name


class ChangeKind(Enum):
    """Kind of parameter change - matches Renderer.SEQ, RAN"""
    SEQ = 0  # Sequential change
    RAN = 1  # Random change

    @classmethod
    def from_string(cls, s: str) -> 'ChangeKind':
        return cls[s.upper()]

    def to_xml_string(self) -> str:
        return self.name


class Motion(Enum):
    """Direction of parameter change - matches Renderer.DOWN, PING_PONG, UP"""
    DOWN = -1
    PING_PONG = 0
    UP = 1

    @classmethod
    def from_string(cls, s: str) -> 'Motion':
        return cls[s.upper()]

    def to_xml_string(self) -> str:
        return self.name


class Cycle(Enum):
    """Cycle pattern for parameter changes - matches Renderer constants"""
    CONSTANT = 0       # Change continuously without pausing
    ONCE = 1           # Change once then stop
    ONCE_REVERT = 2    # Change once then revert
    PAUSING = 3        # Change with fixed pause intervals
    PAUSING_RANDOM = 4 # Change with random pause intervals

    @classmethod
    def from_string(cls, s: str) -> 'Cycle':
        return cls[s.upper()]

    def to_xml_string(self) -> str:
        return self.name


class Scale(Enum):
    """Scale at which changes are applied - matches Renderer.SPRITE, POLY, POINT"""
    SPRITE = 0  # Update at sprite level
    POLY = 1    # Update at polygon level
    POINT = 2   # Update at point level

    @classmethod
    def from_string(cls, s: str) -> 'Scale':
        return cls[s.upper()]

    def to_xml_string(self) -> str:
        return self.name


class ColorChannel(Enum):
    """Color channel for pause targeting - matches Renderer channel constants"""
    RED = 0
    GREEN = 1
    BLUE = 2
    ALPHA = 3

    @classmethod
    def from_string(cls, s: str) -> 'ColorChannel':
        return cls[s.upper()]

    def to_xml_string(self) -> str:
        return self.name


class PlaybackMode(Enum):
    """Renderer set playback mode"""
    STATIC = 0      # No renderer switching
    SEQUENTIAL = 1  # Cycle through renderers in order
    RANDOM = 2      # Randomly select renderers

    @classmethod
    def from_string(cls, s: str) -> 'PlaybackMode':
        return cls[s.upper()]

    def to_xml_string(self) -> str:
        return self.name
