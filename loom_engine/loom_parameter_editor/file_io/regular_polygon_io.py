"""
Read/write standalone regular polygon XML files.
These are editor-only asset files stored in the regularPolygons/ project folder.
"""
import xml.etree.ElementTree as ET
from models.polygon_config import RegularPolygonParams


class RegularPolygonIO:
    """IO for standalone regular polygon XML files."""

    @staticmethod
    def load(filepath: str) -> tuple:
        """Load a regular polygon definition from an XML file.

        Returns:
            (name, RegularPolygonParams) tuple
        """
        tree = ET.parse(filepath)
        root = tree.getroot()

        name = ""
        name_elem = root.find("name")
        if name_elem is not None and name_elem.text:
            name = name_elem.text.strip()

        params = RegularPolygonParams()

        def _float(tag, default):
            elem = root.find(tag)
            if elem is not None and elem.text:
                try:
                    return float(elem.text.strip())
                except ValueError:
                    pass
            return default

        def _int(tag, default):
            elem = root.find(tag)
            if elem is not None and elem.text:
                try:
                    return int(elem.text.strip())
                except ValueError:
                    pass
            return default

        params.total_points = _int("totalPoints", 4)
        params.internal_radius = _float("internalRadius", 0.5)
        params.offset = _float("offset", 0.0)
        params.scale_x = _float("scaleX", 1.0)
        params.scale_y = _float("scaleY", 1.0)
        params.rotation_angle = _float("rotationAngle", 0.0)
        params.trans_x = _float("transX", 0.5)
        params.trans_y = _float("transY", 0.5)

        def _bool(tag, default):
            elem = root.find(tag)
            if elem is not None and elem.text:
                return elem.text.strip().lower() in ("true", "1", "yes")
            return default

        params.positive_synch = _bool("positiveSynch", True)
        params.synch_multiplier = _float("synchMultiplier", 1.0)

        return (name, params)

    @staticmethod
    def save(name: str, params: RegularPolygonParams, filepath: str) -> None:
        """Save a regular polygon definition to an XML file."""
        root = ET.Element("regularPolygon")

        ET.SubElement(root, "name").text = name
        ET.SubElement(root, "shapeType").text = "REGULAR_POLYGON"
        ET.SubElement(root, "totalPoints").text = str(params.total_points)
        ET.SubElement(root, "internalRadius").text = str(params.internal_radius)
        ET.SubElement(root, "offset").text = str(params.offset)
        ET.SubElement(root, "scaleX").text = str(params.scale_x)
        ET.SubElement(root, "scaleY").text = str(params.scale_y)
        ET.SubElement(root, "rotationAngle").text = str(params.rotation_angle)
        ET.SubElement(root, "transX").text = str(params.trans_x)
        ET.SubElement(root, "transY").text = str(params.trans_y)
        ET.SubElement(root, "positiveSynch").text = str(params.positive_synch).lower()
        ET.SubElement(root, "synchMultiplier").text = str(params.synch_multiplier)

        tree = ET.ElementTree(root)
        ET.indent(tree, space="    ")
        tree.write(filepath, encoding="unicode")
