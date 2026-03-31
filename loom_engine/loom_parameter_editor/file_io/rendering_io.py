"""
XML I/O for rendering configuration files.
"""
from lxml import etree
from typing import Optional
from models.rendering import (
    Color, SizeChange, ColorChange, FillColorChange,
    BrushConfig, MeanderConfig, StencilConfig, Renderer, RendererSet, RendererSetLibrary
)
from models.constants import (
    RenderMode, ChangeKind, Motion, Cycle, Scale, ColorChannel, PlaybackMode,
    BrushDrawMode, PostCompletionMode
)


class RenderingIO:
    """Handles reading and writing rendering.xml files."""

    VERSION = "1.0"

    @classmethod
    def load(cls, file_path: str) -> RendererSetLibrary:
        """Load a RendererSetLibrary from an XML file."""
        tree = etree.parse(file_path)
        root = tree.getroot()

        if root.tag != "RenderingConfig":
            raise ValueError(f"Expected RenderingConfig root element, got {root.tag}")

        library_elem = root.find("RendererSetLibrary")
        if library_elem is None:
            raise ValueError("No RendererSetLibrary element found")

        return cls._parse_library(library_elem)

    @classmethod
    def save(cls, library: RendererSetLibrary, file_path: str) -> None:
        """Save a RendererSetLibrary to an XML file."""
        root = etree.Element("RenderingConfig", version=cls.VERSION)
        root.append(cls._build_library(library))

        tree = etree.ElementTree(root)
        tree.write(file_path, pretty_print=True, xml_declaration=True, encoding="UTF-8")

    @classmethod
    def _parse_library(cls, elem: etree._Element) -> RendererSetLibrary:
        """Parse a RendererSetLibrary element."""
        name = elem.get("name", "Library")
        library = RendererSetLibrary(name=name)

        for set_elem in elem.findall("RendererSet"):
            library.add_renderer_set(cls._parse_renderer_set(set_elem))

        return library

    @classmethod
    def _parse_renderer_set(cls, elem: etree._Element) -> RendererSet:
        """Parse a RendererSet element."""
        name = elem.get("name", "Set")
        renderer_set = RendererSet(name=name)

        # Parse playback config
        playback_elem = elem.find("PlaybackConfig")
        if playback_elem is not None:
            mode_elem = playback_elem.find("Mode")
            if mode_elem is not None and mode_elem.text:
                renderer_set.playback_mode = PlaybackMode.from_string(mode_elem.text.strip())

            pref_elem = playback_elem.find("PreferredRenderer")
            if pref_elem is not None and pref_elem.text:
                renderer_set.preferred_renderer = pref_elem.text.strip()

            prob_elem = playback_elem.find("PreferredProbability")
            if prob_elem is not None and prob_elem.text:
                renderer_set.preferred_probability = float(prob_elem.text.strip())

            modify_elem = playback_elem.find("ModifyInternalParameters")
            if modify_elem is not None and modify_elem.text:
                renderer_set.modify_internal_parameters = modify_elem.text.strip().lower() == "true"

        # Parse enabled renderers (direct children)
        for renderer_elem in elem.findall("Renderer"):
            renderer = cls._parse_renderer(renderer_elem)
            renderer.enabled = True
            renderer_set.add_renderer(renderer)

        # Parse disabled renderers (inside EditorDisabled wrapper)
        disabled_elem = elem.find("EditorDisabled")
        if disabled_elem is not None:
            for renderer_elem in disabled_elem.findall("Renderer"):
                renderer = cls._parse_renderer(renderer_elem)
                renderer.enabled = False
                renderer_set.add_renderer(renderer)

        return renderer_set

    @classmethod
    def _parse_renderer(cls, elem: etree._Element) -> Renderer:
        """Parse a Renderer element."""
        name = elem.get("name", "Renderer")
        renderer = Renderer(name=name)

        # Basic properties
        mode_elem = elem.find("Mode")
        if mode_elem is not None and mode_elem.text:
            renderer.mode = RenderMode.from_string(mode_elem.text.strip())

        stroke_width_elem = elem.find("StrokeWidth")
        if stroke_width_elem is not None and stroke_width_elem.text:
            renderer.stroke_width = float(stroke_width_elem.text.strip())

        stroke_color_elem = elem.find("StrokeColor")
        if stroke_color_elem is not None:
            renderer.stroke_color = cls._parse_color(stroke_color_elem)

        fill_color_elem = elem.find("FillColor")
        if fill_color_elem is not None:
            renderer.fill_color = cls._parse_color(fill_color_elem)

        point_size_elem = elem.find("PointSize")
        if point_size_elem is not None and point_size_elem.text:
            renderer.point_size = float(point_size_elem.text.strip())

        hold_length_elem = elem.find("HoldLength")
        if hold_length_elem is not None and hold_length_elem.text:
            renderer.hold_length = int(hold_length_elem.text.strip())

        # Point style
        point_style_elem = elem.find("PointStyle")
        if point_style_elem is not None:
            renderer.point_stroked = point_style_elem.get("stroked", "true").lower() == "true"
            renderer.point_filled = point_style_elem.get("filled", "true").lower() == "true"

        # Changes
        changes_elem = elem.find("Changes")
        if changes_elem is not None:
            stroke_width_change_elem = changes_elem.find("StrokeWidthChange")
            if stroke_width_change_elem is not None:
                renderer.stroke_width_change = cls._parse_size_change(stroke_width_change_elem)

            stroke_color_change_elem = changes_elem.find("StrokeColorChange")
            if stroke_color_change_elem is not None:
                renderer.stroke_color_change = cls._parse_color_change(stroke_color_change_elem)

            fill_color_change_elem = changes_elem.find("FillColorChange")
            if fill_color_change_elem is not None:
                renderer.fill_color_change = cls._parse_fill_color_change(fill_color_change_elem)

            point_size_change_elem = changes_elem.find("PointSizeChange")
            if point_size_change_elem is not None:
                renderer.point_size_change = cls._parse_size_change(point_size_change_elem)

        # Parse brush config (for BRUSHED mode)
        brush_config_elem = elem.find("BrushConfig")
        if brush_config_elem is not None:
            renderer.brush_config = cls._parse_brush_config(brush_config_elem)

        # Parse stencil config (for STAMPED mode)
        stencil_config_elem = elem.find("StencilConfig")
        if stencil_config_elem is not None:
            renderer.stencil_config = cls._parse_stencil_config(stencil_config_elem)

        return renderer

    @classmethod
    def _parse_color(cls, elem: etree._Element) -> Color:
        """Parse a color from element attributes."""
        return Color(
            r=int(elem.get("r", "0")),
            g=int(elem.get("g", "0")),
            b=int(elem.get("b", "0")),
            a=int(elem.get("a", "255"))
        )

    @classmethod
    def _parse_size_change(cls, elem: etree._Element) -> SizeChange:
        """Parse a size change configuration."""
        change = SizeChange()
        change.enabled = elem.get("enabled", "false").lower() == "true"

        kind_elem = elem.find("Kind")
        if kind_elem is not None and kind_elem.text:
            change.kind = ChangeKind.from_string(kind_elem.text.strip())

        motion_elem = elem.find("Motion")
        if motion_elem is not None and motion_elem.text:
            change.motion = Motion.from_string(motion_elem.text.strip())

        cycle_elem = elem.find("Cycle")
        if cycle_elem is not None and cycle_elem.text:
            change.cycle = Cycle.from_string(cycle_elem.text.strip())

        scale_elem = elem.find("Scale")
        if scale_elem is not None and scale_elem.text:
            change.scale = Scale.from_string(scale_elem.text.strip())

        min_elem = elem.find("Min")
        if min_elem is not None and min_elem.text:
            change.min_val = float(min_elem.text.strip())

        max_elem = elem.find("Max")
        if max_elem is not None and max_elem.text:
            change.max_val = float(max_elem.text.strip())

        increment_elem = elem.find("Increment")
        if increment_elem is not None and increment_elem.text:
            change.increment = float(increment_elem.text.strip())

        pause_max_elem = elem.find("PauseMax")
        if pause_max_elem is not None and pause_max_elem.text:
            change.pause_max = int(pause_max_elem.text.strip())

        size_pal_elem = elem.find("SizePalette")
        if size_pal_elem is not None:
            change.size_palette = [
                float(e.text.strip())
                for e in size_pal_elem.findall("PaletteEntry")
                if e.text
            ]

        return change

    @classmethod
    def _parse_color_change(cls, elem: etree._Element) -> ColorChange:
        """Parse a color change configuration."""
        change = ColorChange()
        change.enabled = elem.get("enabled", "false").lower() == "true"

        kind_elem = elem.find("Kind")
        if kind_elem is not None and kind_elem.text:
            change.kind = ChangeKind.from_string(kind_elem.text.strip())

        motion_elem = elem.find("Motion")
        if motion_elem is not None and motion_elem.text:
            change.motion = Motion.from_string(motion_elem.text.strip())

        cycle_elem = elem.find("Cycle")
        if cycle_elem is not None and cycle_elem.text:
            change.cycle = Cycle.from_string(cycle_elem.text.strip())

        scale_elem = elem.find("Scale")
        if scale_elem is not None and scale_elem.text:
            change.scale = Scale.from_string(scale_elem.text.strip())

        min_elem = elem.find("Min")
        if min_elem is not None:
            change.min_color = cls._parse_color(min_elem)

        max_elem = elem.find("Max")
        if max_elem is not None:
            change.max_color = cls._parse_color(max_elem)

        increment_elem = elem.find("Increment")
        if increment_elem is not None:
            change.increment = cls._parse_color(increment_elem)

        pause_max_elem = elem.find("PauseMax")
        if pause_max_elem is not None and pause_max_elem.text:
            change.pause_max = int(pause_max_elem.text.strip())

        palette_elem = elem.find("Palette")
        if palette_elem is not None:
            change.palette = [
                cls._parse_color(ce)
                for ce in palette_elem.findall("PaletteColor")
            ]

        pause_channel_elem = elem.find("PauseChannel")
        if pause_channel_elem is not None and pause_channel_elem.text:
            change.pause_channel = ColorChannel.from_string(pause_channel_elem.text.strip())

        pause_color_min_elem = elem.find("PauseColorMin")
        if pause_color_min_elem is not None:
            change.pause_color_min = cls._parse_color(pause_color_min_elem)

        pause_color_max_elem = elem.find("PauseColorMax")
        if pause_color_max_elem is not None:
            change.pause_color_max = cls._parse_color(pause_color_max_elem)

        return change

    @classmethod
    def _parse_fill_color_change(cls, elem: etree._Element) -> FillColorChange:
        """Parse a fill color change configuration."""
        base = cls._parse_color_change(elem)
        return FillColorChange(
            enabled=base.enabled,
            kind=base.kind,
            motion=base.motion,
            cycle=base.cycle,
            scale=base.scale,
            min_color=base.min_color,
            max_color=base.max_color,
            increment=base.increment,
            pause_max=base.pause_max,
            palette=base.palette,
            pause_channel=base.pause_channel,
            pause_color_min=base.pause_color_min,
            pause_color_max=base.pause_color_max
        )

    @classmethod
    def _build_library(cls, library: RendererSetLibrary) -> etree._Element:
        """Build a RendererSetLibrary XML element."""
        elem = etree.Element("RendererSetLibrary", name=library.name)

        for renderer_set in library.renderer_sets:
            elem.append(cls._build_renderer_set(renderer_set))

        return elem

    @classmethod
    def _build_renderer_set(cls, renderer_set: RendererSet) -> etree._Element:
        """Build a RendererSet XML element."""
        elem = etree.Element("RendererSet", name=renderer_set.name)

        # Playback config
        playback_elem = etree.SubElement(elem, "PlaybackConfig")
        etree.SubElement(playback_elem, "Mode").text = renderer_set.playback_mode.to_xml_string()
        etree.SubElement(playback_elem, "PreferredRenderer").text = renderer_set.preferred_renderer
        etree.SubElement(playback_elem, "PreferredProbability").text = str(renderer_set.preferred_probability)
        etree.SubElement(playback_elem, "ModifyInternalParameters").text = str(renderer_set.modify_internal_parameters).lower()

        # Write enabled renderers as direct children (visible to Scala)
        for renderer in renderer_set.renderers:
            if renderer.enabled:
                elem.append(cls._build_renderer(renderer))

        # Write disabled renderers inside EditorDisabled wrapper (invisible to Scala)
        disabled = [r for r in renderer_set.renderers if not r.enabled]
        if disabled:
            disabled_elem = etree.SubElement(elem, "EditorDisabled")
            for renderer in disabled:
                disabled_elem.append(cls._build_renderer(renderer))

        return elem

    @classmethod
    def _build_renderer(cls, renderer: Renderer) -> etree._Element:
        """Build a Renderer XML element."""
        elem = etree.Element("Renderer", name=renderer.name)

        # Basic properties
        etree.SubElement(elem, "Mode").text = renderer.mode.to_xml_string()
        etree.SubElement(elem, "StrokeWidth").text = str(renderer.stroke_width)
        cls._build_color(elem, "StrokeColor", renderer.stroke_color)
        cls._build_color(elem, "FillColor", renderer.fill_color)
        etree.SubElement(elem, "PointSize").text = str(renderer.point_size)
        etree.SubElement(elem, "HoldLength").text = str(renderer.hold_length)

        # Point style
        point_style_elem = etree.SubElement(elem, "PointStyle")
        point_style_elem.set("stroked", str(renderer.point_stroked).lower())
        point_style_elem.set("filled", str(renderer.point_filled).lower())

        # Changes (only include if any are enabled)
        if renderer.has_any_changes():
            changes_elem = etree.SubElement(elem, "Changes")

            if renderer.stroke_width_change.enabled:
                changes_elem.append(cls._build_size_change("StrokeWidthChange", renderer.stroke_width_change))

            if renderer.stroke_color_change.enabled:
                changes_elem.append(cls._build_color_change("StrokeColorChange", renderer.stroke_color_change))

            if renderer.fill_color_change.enabled:
                changes_elem.append(cls._build_fill_color_change("FillColorChange", renderer.fill_color_change))

            if renderer.point_size_change.enabled:
                changes_elem.append(cls._build_size_change("PointSizeChange", renderer.point_size_change))

        # Build brush config (for BRUSHED mode)
        if renderer.brush_config is not None:
            elem.append(cls._build_brush_config(renderer.brush_config))

        # Build stencil config (for STAMPED mode)
        if renderer.stencil_config is not None:
            elem.append(cls._build_stencil_config(renderer.stencil_config))

        return elem

    @classmethod
    def _build_color(cls, parent: etree._Element, tag: str, color: Color) -> etree._Element:
        """Build a color element with RGBA attributes."""
        elem = etree.SubElement(parent, tag)
        elem.set("r", str(color.r))
        elem.set("g", str(color.g))
        elem.set("b", str(color.b))
        elem.set("a", str(color.a))
        return elem

    @classmethod
    def _build_size_change(cls, tag: str, change: SizeChange) -> etree._Element:
        """Build a size change element."""
        elem = etree.Element(tag)
        elem.set("enabled", str(change.enabled).lower())

        etree.SubElement(elem, "Kind").text = change.kind.to_xml_string()
        etree.SubElement(elem, "Motion").text = change.motion.to_xml_string()
        etree.SubElement(elem, "Cycle").text = change.cycle.to_xml_string()
        etree.SubElement(elem, "Scale").text = change.scale.to_xml_string()

        if change.kind in (ChangeKind.SEQ, ChangeKind.RAN):
            pal_elem = etree.SubElement(elem, "SizePalette")
            for v in change.size_palette:
                etree.SubElement(pal_elem, "PaletteEntry").text = str(v)
        else:
            etree.SubElement(elem, "Min").text = str(change.min_val)
            etree.SubElement(elem, "Max").text = str(change.max_val)
            etree.SubElement(elem, "Increment").text = str(change.increment)

        etree.SubElement(elem, "PauseMax").text = str(change.pause_max)

        return elem

    @classmethod
    def _build_color_change(cls, tag: str, change: ColorChange) -> etree._Element:
        """Build a color change element."""
        elem = etree.Element(tag)
        elem.set("enabled", str(change.enabled).lower())

        etree.SubElement(elem, "Kind").text = change.kind.to_xml_string()
        etree.SubElement(elem, "Motion").text = change.motion.to_xml_string()
        etree.SubElement(elem, "Cycle").text = change.cycle.to_xml_string()
        etree.SubElement(elem, "Scale").text = change.scale.to_xml_string()

        is_palette = change.kind in (ChangeKind.SEQ, ChangeKind.RAN)
        if is_palette:
            pal_elem = etree.SubElement(elem, "Palette")
            for c in change.palette:
                ce = etree.SubElement(pal_elem, "PaletteColor")
                ce.set("r", str(c.r))
                ce.set("g", str(c.g))
                ce.set("b", str(c.b))
                ce.set("a", str(c.a))
        else:
            min_elem = etree.SubElement(elem, "Min")
            min_elem.set("r", str(change.min_color.r))
            min_elem.set("g", str(change.min_color.g))
            min_elem.set("b", str(change.min_color.b))
            min_elem.set("a", str(change.min_color.a))

            max_elem = etree.SubElement(elem, "Max")
            max_elem.set("r", str(change.max_color.r))
            max_elem.set("g", str(change.max_color.g))
            max_elem.set("b", str(change.max_color.b))
            max_elem.set("a", str(change.max_color.a))

            inc_elem = etree.SubElement(elem, "Increment")
            inc_elem.set("r", str(change.increment.r))
            inc_elem.set("g", str(change.increment.g))
            inc_elem.set("b", str(change.increment.b))
            inc_elem.set("a", str(change.increment.a))

        etree.SubElement(elem, "PauseMax").text = str(change.pause_max)

        if not is_palette:
            etree.SubElement(elem, "PauseChannel").text = change.pause_channel.to_xml_string()
            pause_min_elem = etree.SubElement(elem, "PauseColorMin")
            pause_min_elem.set("r", str(change.pause_color_min.r))
            pause_min_elem.set("g", str(change.pause_color_min.g))
            pause_min_elem.set("b", str(change.pause_color_min.b))
            pause_min_elem.set("a", str(change.pause_color_min.a))
            pause_max_elem = etree.SubElement(elem, "PauseColorMax")
            pause_max_elem.set("r", str(change.pause_color_max.r))
            pause_max_elem.set("g", str(change.pause_color_max.g))
            pause_max_elem.set("b", str(change.pause_color_max.b))
            pause_max_elem.set("a", str(change.pause_color_max.a))

        return elem

    @classmethod
    def _build_fill_color_change(cls, tag: str, change: FillColorChange) -> etree._Element:
        """Build a fill color change element."""
        return cls._build_color_change(tag, change)

    @classmethod
    def _parse_brush_config(cls, elem: etree._Element) -> BrushConfig:
        """Parse a BrushConfig element."""
        config = BrushConfig()

        brush_names_elem = elem.find("BrushNames")
        if brush_names_elem is not None:
            names = [b.text.strip() for b in brush_names_elem.findall("Brush") if b.text]
            if names:
                config.brush_names = names

        brush_enabled_elem = elem.find("BrushEnabled")
        if brush_enabled_elem is not None:
            enabled = [e.text.strip().lower() != "false"
                       for e in brush_enabled_elem.findall("Enabled")]
            if enabled:
                config.brush_enabled = enabled
        else:
            # Legacy: default all enabled to match brush_names length
            config.brush_enabled = [True] * len(config.brush_names)

        draw_mode_elem = elem.find("DrawMode")
        if draw_mode_elem is not None and draw_mode_elem.text:
            try:
                config.draw_mode = BrushDrawMode.from_string(draw_mode_elem.text.strip())
            except (KeyError, ValueError):
                pass

        spacing_elem = elem.find("StampSpacing")
        if spacing_elem is not None and spacing_elem.text:
            config.stamp_spacing = float(spacing_elem.text.strip())

        easing_elem = elem.find("SpacingEasing")
        if easing_elem is not None and easing_elem.text:
            config.spacing_easing = easing_elem.text.strip()

        tangent_elem = elem.find("FollowTangent")
        if tangent_elem is not None and tangent_elem.text:
            config.follow_tangent = tangent_elem.text.strip().lower() == "true"

        perp_min_elem = elem.find("PerpendicularJitterMin")
        if perp_min_elem is not None and perp_min_elem.text:
            config.perpendicular_jitter_min = float(perp_min_elem.text.strip())

        perp_max_elem = elem.find("PerpendicularJitterMax")
        if perp_max_elem is not None and perp_max_elem.text:
            config.perpendicular_jitter_max = float(perp_max_elem.text.strip())

        scale_min_elem = elem.find("ScaleMin")
        if scale_min_elem is not None and scale_min_elem.text:
            config.scale_min = float(scale_min_elem.text.strip())

        scale_max_elem = elem.find("ScaleMax")
        if scale_max_elem is not None and scale_max_elem.text:
            config.scale_max = float(scale_max_elem.text.strip())

        opacity_min_elem = elem.find("OpacityMin")
        if opacity_min_elem is not None and opacity_min_elem.text:
            config.opacity_min = float(opacity_min_elem.text.strip())

        opacity_max_elem = elem.find("OpacityMax")
        if opacity_max_elem is not None and opacity_max_elem.text:
            config.opacity_max = float(opacity_max_elem.text.strip())

        spf_elem = elem.find("StampsPerFrame")
        if spf_elem is not None and spf_elem.text:
            config.stamps_per_frame = int(spf_elem.text.strip())

        ac_elem = elem.find("AgentCount")
        if ac_elem is not None and ac_elem.text:
            config.agent_count = int(ac_elem.text.strip())

        pcm_elem = elem.find("PostCompletionMode")
        if pcm_elem is not None and pcm_elem.text:
            try:
                config.post_completion_mode = PostCompletionMode.from_string(pcm_elem.text.strip())
            except (KeyError, ValueError):
                pass

        blur_elem = elem.find("BlurRadius")
        if blur_elem is not None and blur_elem.text:
            config.blur_radius = int(blur_elem.text.strip())

        mc_elem = elem.find("MeanderConfig")
        if mc_elem is not None:
            config.meander_config = cls._parse_meander_config(mc_elem)

        psi_elem = elem.find("PressureSizeInfluence")
        if psi_elem is not None and psi_elem.text:
            config.pressure_size_influence = float(psi_elem.text.strip())

        pai_elem = elem.find("PressureAlphaInfluence")
        if pai_elem is not None and pai_elem.text:
            config.pressure_alpha_influence = float(pai_elem.text.strip())

        return config

    @classmethod
    def _parse_meander_config(cls, elem: etree._Element) -> MeanderConfig:
        mc = MeanderConfig()
        def _bool(tag, default):
            e = elem.find(tag)
            return e.text.strip().lower() == "true" if (e is not None and e.text) else default
        def _float(tag, default):
            e = elem.find(tag)
            try: return float(e.text.strip()) if (e is not None and e.text) else default
            except ValueError: return default
        def _int(tag, default):
            e = elem.find(tag)
            try: return int(e.text.strip()) if (e is not None and e.text) else default
            except ValueError: return default
        mc.enabled                   = _bool("Enabled", mc.enabled)
        mc.amplitude                 = _float("Amplitude", mc.amplitude)
        mc.frequency                 = _float("Frequency", mc.frequency)
        mc.samples                   = _int("Samples", mc.samples)
        mc.seed                      = _int("Seed", mc.seed)
        mc.animated                  = _bool("Animated", mc.animated)
        mc.anim_speed                = _float("AnimSpeed", mc.anim_speed)
        mc.scale_along_path          = _bool("ScaleAlongPath", mc.scale_along_path)
        mc.scale_along_path_frequency = _float("ScaleAlongPathFrequency", mc.scale_along_path_frequency)
        mc.scale_along_path_range    = _float("ScaleAlongPathRange", mc.scale_along_path_range)
        return mc

    @classmethod
    def _parse_stencil_config(cls, elem: etree._Element) -> StencilConfig:
        """Parse a StencilConfig element."""
        config = StencilConfig()

        stencil_names_elem = elem.find("StencilNames")
        if stencil_names_elem is not None:
            names = [s.text.strip() for s in stencil_names_elem.findall("Stencil") if s.text]
            if names:
                config.stencil_names = names

        stencil_enabled_elem = elem.find("StencilEnabled")
        if stencil_enabled_elem is not None:
            enabled = [e.text.strip().lower() != "false"
                       for e in stencil_enabled_elem.findall("Enabled")]
            if enabled:
                config.stencil_enabled = enabled
        else:
            config.stencil_enabled = [True] * len(config.stencil_names)

        draw_mode_elem = elem.find("DrawMode")
        if draw_mode_elem is not None and draw_mode_elem.text:
            try:
                config.draw_mode = BrushDrawMode.from_string(draw_mode_elem.text.strip())
            except (KeyError, ValueError):
                pass

        spacing_elem = elem.find("StampSpacing")
        if spacing_elem is not None and spacing_elem.text:
            config.stamp_spacing = float(spacing_elem.text.strip())

        easing_elem = elem.find("SpacingEasing")
        if easing_elem is not None and easing_elem.text:
            config.spacing_easing = easing_elem.text.strip()

        tangent_elem = elem.find("FollowTangent")
        if tangent_elem is not None and tangent_elem.text:
            config.follow_tangent = tangent_elem.text.strip().lower() == "true"

        perp_min_elem = elem.find("PerpendicularJitterMin")
        if perp_min_elem is not None and perp_min_elem.text:
            config.perpendicular_jitter_min = float(perp_min_elem.text.strip())

        perp_max_elem = elem.find("PerpendicularJitterMax")
        if perp_max_elem is not None and perp_max_elem.text:
            config.perpendicular_jitter_max = float(perp_max_elem.text.strip())

        scale_min_elem = elem.find("ScaleMin")
        if scale_min_elem is not None and scale_min_elem.text:
            config.scale_min = float(scale_min_elem.text.strip())

        scale_max_elem = elem.find("ScaleMax")
        if scale_max_elem is not None and scale_max_elem.text:
            config.scale_max = float(scale_max_elem.text.strip())

        spf_elem = elem.find("StampsPerFrame")
        if spf_elem is not None and spf_elem.text:
            config.stamps_per_frame = int(spf_elem.text.strip())

        ac_elem = elem.find("AgentCount")
        if ac_elem is not None and ac_elem.text:
            config.agent_count = int(ac_elem.text.strip())

        pcm_elem = elem.find("PostCompletionMode")
        if pcm_elem is not None and pcm_elem.text:
            try:
                config.post_completion_mode = PostCompletionMode.from_string(pcm_elem.text.strip())
            except (KeyError, ValueError):
                pass

        opacity_change_elem = elem.find("OpacityChange")
        if opacity_change_elem is not None:
            config.opacity_change = cls._parse_size_change(opacity_change_elem)

        return config

    @classmethod
    def _build_stencil_config(cls, config: StencilConfig) -> etree._Element:
        """Build a StencilConfig XML element."""
        elem = etree.Element("StencilConfig")

        stencil_names_elem = etree.SubElement(elem, "StencilNames")
        for name in config.stencil_names:
            etree.SubElement(stencil_names_elem, "Stencil").text = name

        stencil_enabled_elem = etree.SubElement(elem, "StencilEnabled")
        for i, name in enumerate(config.stencil_names):
            enabled = config.stencil_enabled[i] if i < len(config.stencil_enabled) else True
            etree.SubElement(stencil_enabled_elem, "Enabled").text = str(enabled).lower()

        etree.SubElement(elem, "DrawMode").text = config.draw_mode.to_xml_string()
        etree.SubElement(elem, "StampSpacing").text = str(config.stamp_spacing)
        etree.SubElement(elem, "SpacingEasing").text = config.spacing_easing
        etree.SubElement(elem, "FollowTangent").text = str(config.follow_tangent).lower()
        etree.SubElement(elem, "PerpendicularJitterMin").text = str(config.perpendicular_jitter_min)
        etree.SubElement(elem, "PerpendicularJitterMax").text = str(config.perpendicular_jitter_max)
        etree.SubElement(elem, "ScaleMin").text = str(config.scale_min)
        etree.SubElement(elem, "ScaleMax").text = str(config.scale_max)
        etree.SubElement(elem, "StampsPerFrame").text = str(config.stamps_per_frame)
        etree.SubElement(elem, "AgentCount").text = str(config.agent_count)
        etree.SubElement(elem, "PostCompletionMode").text = config.post_completion_mode.to_xml_string()

        # Opacity change animation
        elem.append(cls._build_size_change("OpacityChange", config.opacity_change))

        return elem

    @classmethod
    def _build_brush_config(cls, config: BrushConfig) -> etree._Element:
        """Build a BrushConfig XML element."""
        elem = etree.Element("BrushConfig")

        brush_names_elem = etree.SubElement(elem, "BrushNames")
        for name in config.brush_names:
            etree.SubElement(brush_names_elem, "Brush").text = name

        brush_enabled_elem = etree.SubElement(elem, "BrushEnabled")
        for i, name in enumerate(config.brush_names):
            enabled = config.brush_enabled[i] if i < len(config.brush_enabled) else True
            etree.SubElement(brush_enabled_elem, "Enabled").text = str(enabled).lower()

        etree.SubElement(elem, "DrawMode").text = config.draw_mode.to_xml_string()
        etree.SubElement(elem, "StampSpacing").text = str(config.stamp_spacing)
        etree.SubElement(elem, "SpacingEasing").text = config.spacing_easing
        etree.SubElement(elem, "FollowTangent").text = str(config.follow_tangent).lower()
        etree.SubElement(elem, "PerpendicularJitterMin").text = str(config.perpendicular_jitter_min)
        etree.SubElement(elem, "PerpendicularJitterMax").text = str(config.perpendicular_jitter_max)
        etree.SubElement(elem, "ScaleMin").text = str(config.scale_min)
        etree.SubElement(elem, "ScaleMax").text = str(config.scale_max)
        etree.SubElement(elem, "OpacityMin").text = str(config.opacity_min)
        etree.SubElement(elem, "OpacityMax").text = str(config.opacity_max)
        etree.SubElement(elem, "StampsPerFrame").text = str(config.stamps_per_frame)
        etree.SubElement(elem, "AgentCount").text = str(config.agent_count)
        etree.SubElement(elem, "PostCompletionMode").text = config.post_completion_mode.to_xml_string()
        etree.SubElement(elem, "BlurRadius").text = str(config.blur_radius)

        mc = config.meander_config
        mc_elem = etree.SubElement(elem, "MeanderConfig")
        etree.SubElement(mc_elem, "Enabled").text = str(mc.enabled).lower()
        etree.SubElement(mc_elem, "Amplitude").text = str(mc.amplitude)
        etree.SubElement(mc_elem, "Frequency").text = str(mc.frequency)
        etree.SubElement(mc_elem, "Samples").text = str(mc.samples)
        etree.SubElement(mc_elem, "Seed").text = str(mc.seed)
        etree.SubElement(mc_elem, "Animated").text = str(mc.animated).lower()
        etree.SubElement(mc_elem, "AnimSpeed").text = str(mc.anim_speed)
        etree.SubElement(mc_elem, "ScaleAlongPath").text = str(mc.scale_along_path).lower()
        etree.SubElement(mc_elem, "ScaleAlongPathFrequency").text = str(mc.scale_along_path_frequency)
        etree.SubElement(mc_elem, "ScaleAlongPathRange").text = str(mc.scale_along_path_range)

        etree.SubElement(elem, "PressureSizeInfluence").text = str(config.pressure_size_influence)
        etree.SubElement(elem, "PressureAlphaInfluence").text = str(config.pressure_alpha_influence)

        return elem
