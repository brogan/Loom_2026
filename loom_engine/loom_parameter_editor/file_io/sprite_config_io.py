"""
Sprite configuration XML I/O.

Handles reading and writing sprites.xml files.
XML format matches Scala SpriteConfigLoader expectations.
"""
from lxml import etree
from models.sprite_config import (
    SpriteLibrary, SpriteSet, SpriteDef, SpriteParams, Keyframe, MorphTargetRef
)


class SpriteConfigIO:
    """Read/write sprite configuration XML files."""

    @staticmethod
    def load(file_path: str) -> SpriteLibrary:
        """Load a SpriteLibrary from an XML file."""
        try:
            tree = etree.parse(file_path)
            root = tree.getroot()
            return SpriteConfigIO._parse_config(root)
        except Exception as e:
            print(f"Error loading sprite config from {file_path}: {e}")
            return SpriteLibrary()

    @staticmethod
    def save(library: SpriteLibrary, file_path: str) -> None:
        """Save a SpriteLibrary to an XML file."""
        root = SpriteConfigIO._build_xml(library)
        tree = etree.ElementTree(root)
        tree.write(file_path, pretty_print=True, xml_declaration=True, encoding="UTF-8")

    @staticmethod
    def _parse_config(root: etree._Element) -> SpriteLibrary:
        """Parse the root SpriteConfig element."""
        library = SpriteLibrary()

        # Find SpriteLibrary element
        lib_elem = root.find("SpriteLibrary")
        if lib_elem is not None:
            library.name = lib_elem.get("name", "MainLibrary")

            # Parse each SpriteSet
            for set_elem in lib_elem.findall("SpriteSet"):
                sprite_set = SpriteConfigIO._parse_sprite_set(set_elem)
                library.add(sprite_set)

            # Also check for Sprite elements directly under library (flat structure)
            for sprite_elem in lib_elem.findall("Sprite"):
                # Create a default set if needed
                if not library.sprite_sets:
                    library.add(SpriteSet(name="default"))
                sprite = SpriteConfigIO._parse_sprite(sprite_elem)
                library.sprite_sets[0].add(sprite)

        return library

    @staticmethod
    def _parse_sprite_set(elem: etree._Element) -> SpriteSet:
        """Parse a SpriteSet element."""
        sprite_set = SpriteSet(name=elem.get("name", "default"))

        # Enabled sprites (direct children)
        for sprite_elem in elem.findall("Sprite"):
            sprite = SpriteConfigIO._parse_sprite(sprite_elem)
            sprite.enabled = True
            sprite_set.add(sprite)

        # Disabled sprites (inside EditorDisabled wrapper — Scala ignores this block)
        disabled_elem = elem.find("EditorDisabled")
        if disabled_elem is not None:
            for sprite_elem in disabled_elem.findall("Sprite"):
                sprite = SpriteConfigIO._parse_sprite(sprite_elem)
                sprite.enabled = False
                sprite_set.add(sprite)

        return sprite_set

    @staticmethod
    def _parse_sprite(elem: etree._Element) -> SpriteDef:
        """Parse a Sprite element (Scala SpriteConfigLoader format)."""
        sprite = SpriteDef(name=elem.get("name", "default"))

        # Shape reference: Scala uses shapeSet attribute
        shape_elem = elem.find("Shape")
        if shape_elem is not None:
            sprite.shape_set_name = shape_elem.get("shapeSet", shape_elem.get("set", ""))
            sprite.shape_name = shape_elem.get("name", "")

        # Renderer set reference
        renderer_elem = elem.find("RendererSet")
        if renderer_elem is not None:
            sprite.renderer_set_name = renderer_elem.get("name", "")

        # Position (Scala: direct child <Position x="..." y="..."/>)
        pos_elem = elem.find("Position")
        if pos_elem is not None:
            sprite.params.location_x = float(pos_elem.get("x", "0"))
            sprite.params.location_y = float(pos_elem.get("y", "0"))

        # Scale (Scala: direct child <Scale x="..." y="..."/>)
        scale_elem = elem.find("Scale")
        if scale_elem is not None:
            sprite.params.size_x = float(scale_elem.get("x", "1"))
            sprite.params.size_y = float(scale_elem.get("y", "1"))

        # Rotation (Scala: text content <Rotation>0.0</Rotation>)
        rot_elem = elem.find("Rotation")
        if rot_elem is not None and rot_elem.text:
            try:
                sprite.params.start_rotation = float(rot_elem.text.strip())
            except ValueError:
                pass

        # Animation block (Scala format)
        anim_elem = elem.find("Animation")
        if anim_elem is not None:
            sprite.params.animation_enabled = anim_elem.get("enabled", "true").lower() != "false"

            # Animator type: "random" (default) or "keyframe"
            anim_type = anim_elem.get("type", "")
            if anim_type:
                sprite.animator_type = anim_type

            # Loop mode for keyframe animation
            loop_mode = anim_elem.get("loopMode", "")
            if loop_mode:
                sprite.params.loop_mode = loop_mode

            # Jitter mode
            sprite.params.jitter = anim_elem.get("jitter", "false").lower() == "true"

            td_elem = anim_elem.find("TotalDraws")
            if td_elem is not None and td_elem.text:
                try:
                    sprite.params.total_draws = int(float(td_elem.text.strip()))
                except ValueError:
                    pass

            sr_elem = anim_elem.find("ScaleRange")
            if sr_elem is not None:
                sprite.params.scale_range_x_min = float(sr_elem.get("xMin", "0"))
                sprite.params.scale_range_x_max = float(sr_elem.get("xMax", "0"))
                sprite.params.scale_range_y_min = float(sr_elem.get("yMin", "0"))
                sprite.params.scale_range_y_max = float(sr_elem.get("yMax", "0"))

            rr_elem = anim_elem.find("RotationRange")
            if rr_elem is not None:
                sprite.params.rotation_range_min = float(rr_elem.get("min", "0"))
                sprite.params.rotation_range_max = float(rr_elem.get("max", "0"))

            tr_elem = anim_elem.find("TranslationRange")
            if tr_elem is not None:
                sprite.params.translation_range_x_min = float(tr_elem.get("xMin", "0"))
                sprite.params.translation_range_x_max = float(tr_elem.get("xMax", "0"))
                sprite.params.translation_range_y_min = float(tr_elem.get("yMin", "0"))
                sprite.params.translation_range_y_max = float(tr_elem.get("yMax", "0"))

            # Morph target data — new format: <MorphTargets><MorphTarget file="..." name="..."/>...
            # Backward compat: <MorphTarget polygonSet="..."/> (single target, old format)
            mts_elem = anim_elem.find("MorphTargets")
            if mts_elem is not None:
                refs = []
                for mt_child in mts_elem.findall("MorphTarget"):
                    refs.append(MorphTargetRef(
                        file=mt_child.get("file", ""),
                        name=mt_child.get("name", ""),
                    ))
                sprite.params.morph_targets = refs
                sprite.params.morph_min = float(mts_elem.get("morphMin", "0"))
                sprite.params.morph_max = float(mts_elem.get("morphMax", "1"))
            else:
                # Old single-target format fallback
                mt_elem = anim_elem.find("MorphTarget")
                if mt_elem is not None:
                    ps = mt_elem.get("polygonSet", "")
                    if ps:
                        sprite.params.morph_targets = [MorphTargetRef(file=ps)]
                    sprite.params.morph_min = float(mt_elem.get("morphMin", "0"))
                    sprite.params.morph_max = float(mt_elem.get("morphMax", "1"))

            # Keyframe animation data
            kfs_elem = anim_elem.find("Keyframes")
            if kfs_elem is not None:
                keyframes = []
                for kf_elem in kfs_elem.findall("Keyframe"):
                    kf = Keyframe(
                        draw_cycle=int(kf_elem.get("drawCycle", "0")),
                        pos_x=float(kf_elem.get("posX", "0")),
                        pos_y=float(kf_elem.get("posY", "0")),
                        scale_x=float(kf_elem.get("scaleX", "1")),
                        scale_y=float(kf_elem.get("scaleY", "1")),
                        rotation=float(kf_elem.get("rotation", "0")),
                        easing=kf_elem.get("easing", "LINEAR"),
                        morph_amount=float(kf_elem.get("morphAmount", "0")),
                    )
                    keyframes.append(kf)
                sprite.params.keyframes = keyframes

        # Editor extensions (editor-only fields, ignored by Scala)
        ext_elem = elem.find("EditorExtensions")
        if ext_elem is not None:
            sprite.enabled = ext_elem.get("enabled", "true").lower() == "true"
            # Legacy: read animator type from EditorExtensions if not already set from Animation block
            legacy_animator = ext_elem.get("animator", "")
            if legacy_animator and sprite.animator_type == "random":
                # Map legacy "default" to "random"
                sprite.animator_type = "random" if legacy_animator == "default" else legacy_animator

            rot_off_elem = ext_elem.find("RotationOffset")
            if rot_off_elem is not None:
                sprite.params.rot_offset_x = float(rot_off_elem.get("x", "0"))
                sprite.params.rot_offset_y = float(rot_off_elem.get("y", "0"))

            sf_elem = ext_elem.find("ScaleFactor")
            if sf_elem is not None:
                sprite.params.scale_factor_x = float(sf_elem.get("x", "1"))
                sprite.params.scale_factor_y = float(sf_elem.get("y", "1"))

            rf_elem = ext_elem.find("RotationFactor")
            if rf_elem is not None:
                sprite.params.rotation_factor = float(rf_elem.get("value", "0"))

            spf_elem = ext_elem.find("SpeedFactor")
            if spf_elem is not None:
                sprite.params.speed_factor_x = float(spf_elem.get("x", "0"))
                sprite.params.speed_factor_y = float(spf_elem.get("y", "0"))

        # Legacy format: parse Params block if present (for backwards compatibility)
        params_elem = elem.find("Params")
        if params_elem is not None and pos_elem is None:
            loc_elem = params_elem.find("Location")
            if loc_elem is not None:
                sprite.params.location_x = float(loc_elem.get("x", "0"))
                sprite.params.location_y = float(loc_elem.get("y", "0"))
            size_elem = params_elem.find("Size")
            if size_elem is not None:
                sprite.params.size_x = float(size_elem.get("x", "1"))
                sprite.params.size_y = float(size_elem.get("y", "1"))
            sr_elem = params_elem.find("StartRotation")
            if sr_elem is not None:
                sprite.params.start_rotation = float(sr_elem.get("angle", "0"))

        # Legacy: Enabled element
        enabled_elem = elem.find("Enabled")
        if enabled_elem is not None:
            sprite.enabled = enabled_elem.text.lower() == "true"

        return sprite

    @staticmethod
    def _build_xml(library: SpriteLibrary) -> etree._Element:
        """Build XML from a SpriteLibrary."""
        root = etree.Element("SpriteConfig", version="1.0")

        lib_elem = etree.SubElement(root, "SpriteLibrary", name=library.name)

        for sprite_set in library.sprite_sets:
            set_elem = etree.SubElement(lib_elem, "SpriteSet", name=sprite_set.name)

            # Write enabled sprites as direct children (visible to Scala)
            for sprite in sprite_set.sprites:
                if sprite.enabled:
                    SpriteConfigIO._build_sprite_xml(set_elem, sprite)

            # Write disabled sprites inside EditorDisabled wrapper (invisible to Scala)
            disabled = [s for s in sprite_set.sprites if not s.enabled]
            if disabled:
                disabled_elem = etree.SubElement(set_elem, "EditorDisabled")
                for sprite in disabled:
                    SpriteConfigIO._build_sprite_xml(disabled_elem, sprite)

        return root

    @staticmethod
    def _build_sprite_xml(parent: etree._Element, sprite: SpriteDef) -> None:
        """Build XML for a single sprite (Scala SpriteConfigLoader format)."""
        sprite_elem = etree.SubElement(parent, "Sprite", name=sprite.name)

        # Shape reference: use shapeSet attribute (Scala format)
        if sprite.shape_set_name or sprite.shape_name:
            etree.SubElement(sprite_elem, "Shape",
                             shapeSet=sprite.shape_set_name,
                             name=sprite.shape_name)

        # Renderer set reference
        if sprite.renderer_set_name:
            etree.SubElement(sprite_elem, "RendererSet",
                             name=sprite.renderer_set_name)

        params = sprite.params

        # Position (Scala: direct child with x/y attributes)
        etree.SubElement(sprite_elem, "Position",
                         x=str(params.location_x), y=str(params.location_y))

        # Scale (Scala: direct child with x/y attributes)
        etree.SubElement(sprite_elem, "Scale",
                         x=str(params.size_x), y=str(params.size_y))

        # Rotation (Scala: text content)
        rot_elem = etree.SubElement(sprite_elem, "Rotation")
        rot_elem.text = str(params.start_rotation)

        # Animation block (Scala format)
        anim_attribs = {"enabled": str(params.animation_enabled).lower()}
        # Write animator type (defaults to "random" for backward compat)
        anim_type = sprite.animator_type if sprite.animator_type else "random"
        anim_attribs["type"] = anim_type
        if anim_type in ("keyframe", "keyframe_morph"):
            anim_attribs["loopMode"] = params.loop_mode or "NONE"
        if params.jitter:
            anim_attribs["jitter"] = "true"
        anim_elem = etree.SubElement(sprite_elem, "Animation", **anim_attribs)

        td_elem = etree.SubElement(anim_elem, "TotalDraws")
        td_elem.text = str(params.total_draws)
        etree.SubElement(anim_elem, "ScaleRange",
                         xMin=str(params.scale_range_x_min),
                         xMax=str(params.scale_range_x_max),
                         yMin=str(params.scale_range_y_min),
                         yMax=str(params.scale_range_y_max))
        etree.SubElement(anim_elem, "RotationRange",
                         min=str(params.rotation_range_min),
                         max=str(params.rotation_range_max))
        etree.SubElement(anim_elem, "TranslationRange",
                         xMin=str(params.translation_range_x_min),
                         xMax=str(params.translation_range_x_max),
                         yMin=str(params.translation_range_y_min),
                         yMax=str(params.translation_range_y_max))

        # Morph target chain — new format (written when list is non-empty)
        if params.morph_targets:
            mts_attribs = {}
            if anim_type == "jitter_morph":
                mts_attribs["morphMin"] = str(params.morph_min)
                mts_attribs["morphMax"] = str(params.morph_max)
            mts_elem = etree.SubElement(anim_elem, "MorphTargets", **mts_attribs)
            for ref in params.morph_targets:
                mt_attribs = {"file": ref.file}
                if ref.name:
                    mt_attribs["name"] = ref.name
                etree.SubElement(mts_elem, "MorphTarget", **mt_attribs)

        # Keyframe data (written regardless of mode, so switching modes preserves data)
        if params.keyframes:
            kfs_elem = etree.SubElement(anim_elem, "Keyframes")
            for kf in params.keyframes:
                kf_attribs = {
                    "drawCycle": str(kf.draw_cycle),
                    "posX": str(kf.pos_x),
                    "posY": str(kf.pos_y),
                    "scaleX": str(kf.scale_x),
                    "scaleY": str(kf.scale_y),
                    "rotation": str(kf.rotation),
                    "easing": kf.easing,
                }
                if kf.morph_amount != 0.0:
                    kf_attribs["morphAmount"] = str(kf.morph_amount)
                etree.SubElement(kfs_elem, "Keyframe", **kf_attribs)

        # Editor extensions (editor-only fields, Scala ignores unknown elements)
        ext_elem = etree.SubElement(sprite_elem, "EditorExtensions",
                                    enabled=str(sprite.enabled).lower(),
                                    animator=sprite.animator_type)
        etree.SubElement(ext_elem, "RotationOffset",
                         x=str(params.rot_offset_x), y=str(params.rot_offset_y))
        etree.SubElement(ext_elem, "ScaleFactor",
                         x=str(params.scale_factor_x), y=str(params.scale_factor_y))
        etree.SubElement(ext_elem, "RotationFactor",
                         value=str(params.rotation_factor))
        etree.SubElement(ext_elem, "SpeedFactor",
                         x=str(params.speed_factor_x), y=str(params.speed_factor_y))
