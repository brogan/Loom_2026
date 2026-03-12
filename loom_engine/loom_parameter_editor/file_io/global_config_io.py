"""
XML I/O for GlobalConfig.
Reads and writes global_config.xml files in the format expected by the Scala application.
"""
from typing import Optional
from lxml import etree
from models.global_config import GlobalConfig
from models.rendering import Color


class GlobalConfigIO:
    """Read and write GlobalConfig XML files."""

    @staticmethod
    def load(file_path: str) -> GlobalConfig:
        """Load GlobalConfig from an XML file."""
        tree = etree.parse(file_path)
        root = tree.getroot()
        return GlobalConfigIO._parse_config(root)

    @staticmethod
    def load_from_string(xml_content: str) -> GlobalConfig:
        """Load GlobalConfig from an XML string."""
        root = etree.fromstring(xml_content.encode())
        return GlobalConfigIO._parse_config(root)

    @staticmethod
    def save(config: GlobalConfig, file_path: str) -> None:
        """Save GlobalConfig to an XML file."""
        root = GlobalConfigIO._build_xml(config)
        tree = etree.ElementTree(root)
        tree.write(file_path, encoding="UTF-8", xml_declaration=True, pretty_print=True)

    @staticmethod
    def to_string(config: GlobalConfig) -> str:
        """Convert GlobalConfig to XML string."""
        root = GlobalConfigIO._build_xml(config)
        return etree.tostring(root, encoding="unicode", pretty_print=True)

    @staticmethod
    def _parse_config(root: etree._Element) -> GlobalConfig:
        """Parse GlobalConfig from XML element."""
        return GlobalConfig(
            name=GlobalConfigIO._get_text(root, "Name", "Untitled"),
            note=GlobalConfigIO._get_text(root, "Note", ""),
            width=GlobalConfigIO._get_int(root, "Width", 1080),
            height=GlobalConfigIO._get_int(root, "Height", 1080),
            quality_multiple=GlobalConfigIO._get_int(root, "QualityMultiple", 1),
            scale_image=GlobalConfigIO._get_bool(root, "ScaleImage",
                        GlobalConfigIO._get_bool(root, "ScaleStrokeWidth",
                            GlobalConfigIO._get_bool(root, "Large", False))),
            animating=GlobalConfigIO._get_bool(root, "Animating", False),
            draw_background_once=GlobalConfigIO._get_bool(root, "DrawBackgroundOnce", True),
            fullscreen=GlobalConfigIO._get_bool(root, "Fullscreen", False),
            border_color=GlobalConfigIO._get_color_attrs(root, "BorderColor", Color(0, 0, 0, 255)),
            background_color=GlobalConfigIO._get_color_attrs(root, "BackgroundColor", Color(255, 255, 255, 255)),
            overlay_color=GlobalConfigIO._get_color_attrs(root, "OverlayColor", Color(0, 0, 0, 170)),
            background_image_path=GlobalConfigIO._get_text(root, "BackgroundImage", ""),
            three_d=GlobalConfigIO._get_bool(root, "ThreeD", False),
            camera_view_angle=GlobalConfigIO._get_int(root, "CameraViewAngle", 120),
            subdividing=GlobalConfigIO._get_bool(root, "Subdividing", True),
            serial=GlobalConfigIO._get_bool(root, "Serial", False),
            port=GlobalConfigIO._get_text(root, "Port", "/dev/ttyUSB0"),
            mode=GlobalConfigIO._get_text(root, "Mode", "bytes"),
            quantity=GlobalConfigIO._get_int(root, "Quantity", 4)
        )

    @staticmethod
    def _build_xml(config: GlobalConfig) -> etree._Element:
        """Build XML element from GlobalConfig."""
        root = etree.Element("GlobalConfig", version="1.0")

        # Add comment
        root.append(etree.Comment(" Project identification "))
        GlobalConfigIO._add_element(root, "Name", config.name)
        if config.note:
            GlobalConfigIO._add_element(root, "Note", config.note)

        root.append(etree.Comment(" Canvas dimensions "))
        GlobalConfigIO._add_element(root, "Width", str(config.width))
        GlobalConfigIO._add_element(root, "Height", str(config.height))

        root.append(etree.Comment(" Quality and rendering "))
        GlobalConfigIO._add_element(root, "QualityMultiple", str(config.quality_multiple))
        GlobalConfigIO._add_element(root, "ScaleImage", str(config.scale_image).lower())

        root.append(etree.Comment(" Animation "))
        GlobalConfigIO._add_element(root, "Animating", str(config.animating).lower())
        GlobalConfigIO._add_element(root, "DrawBackgroundOnce", str(config.draw_background_once).lower())

        root.append(etree.Comment(" Display "))
        GlobalConfigIO._add_element(root, "Fullscreen", str(config.fullscreen).lower())
        GlobalConfigIO._add_color_element(root, "BorderColor", config.border_color)
        GlobalConfigIO._add_color_element(root, "BackgroundColor", config.background_color)
        GlobalConfigIO._add_color_element(root, "OverlayColor", config.overlay_color)
        if config.background_image_path:
            GlobalConfigIO._add_element(root, "BackgroundImage", config.background_image_path)

        root.append(etree.Comment(" 3D settings "))
        GlobalConfigIO._add_element(root, "ThreeD", str(config.three_d).lower())
        GlobalConfigIO._add_element(root, "CameraViewAngle", str(config.camera_view_angle))

        root.append(etree.Comment(" Subdivision "))
        GlobalConfigIO._add_element(root, "Subdividing", str(config.subdividing).lower())

        root.append(etree.Comment(" Serial communication (legacy) "))
        GlobalConfigIO._add_element(root, "Serial", str(config.serial).lower())
        GlobalConfigIO._add_element(root, "Port", config.port)
        GlobalConfigIO._add_element(root, "Mode", config.mode)
        GlobalConfigIO._add_element(root, "Quantity", str(config.quantity))

        return root

    @staticmethod
    def _add_element(parent: etree._Element, name: str, text: str) -> None:
        """Add a child element with text content."""
        elem = etree.SubElement(parent, name)
        elem.text = text

    @staticmethod
    def _get_text(root: etree._Element, name: str, default: str) -> str:
        """Get text content of child element, or default if not found."""
        elem = root.find(name)
        if elem is not None and elem.text:
            return elem.text.strip()
        return default

    @staticmethod
    def _get_int(root: etree._Element, name: str, default: int) -> int:
        """Get integer value of child element, or default if not found."""
        text = GlobalConfigIO._get_text(root, name, "")
        if text:
            try:
                return int(text)
            except ValueError:
                pass
        return default

    @staticmethod
    def _get_bool(root: etree._Element, name: str, default: bool) -> bool:
        """Get boolean value of child element, or default if not found."""
        text = GlobalConfigIO._get_text(root, name, "").lower()
        if text == "true":
            return True
        elif text == "false":
            return False
        return default

    @staticmethod
    def _get_color_attrs(root: etree._Element, name: str, default: Color) -> Color:
        """Get color from child element with r, g, b, a XML attributes (Scala format)."""
        elem = root.find(name)
        if elem is None:
            return default
        try:
            r = int(elem.get("r", str(default.r)))
            g = int(elem.get("g", str(default.g)))
            b = int(elem.get("b", str(default.b)))
            a = int(elem.get("a", str(default.a)))
            return Color(r, g, b, a)
        except (ValueError, TypeError):
            return default

    @staticmethod
    def _add_color_element(parent: etree._Element, name: str, color: Color) -> None:
        """Add a color child element with r, g, b, a XML attributes (Scala format)."""
        etree.SubElement(parent, name,
                         r=str(color.r), g=str(color.g),
                         b=str(color.b), a=str(color.a))
