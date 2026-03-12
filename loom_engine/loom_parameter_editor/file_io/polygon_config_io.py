"""
XML I/O for PolygonConfig.
Reads and writes polygons.xml files.
"""
from typing import Optional
from lxml import etree
from models.polygon_config import (
    PolygonSourceType, PolygonType, RegularPolygonParams,
    FileSource, PolygonSetDef, PolygonSetLibrary
)


class PolygonConfigIO:
    """Read and write polygon configuration XML files."""

    @staticmethod
    def load(file_path: str) -> PolygonSetLibrary:
        """Load PolygonSetLibrary from an XML file."""
        tree = etree.parse(file_path)
        root = tree.getroot()
        return PolygonConfigIO._parse_config(root)

    @staticmethod
    def load_from_string(xml_content: str) -> PolygonSetLibrary:
        """Load PolygonSetLibrary from an XML string."""
        root = etree.fromstring(xml_content.encode())
        return PolygonConfigIO._parse_config(root)

    @staticmethod
    def save(library: PolygonSetLibrary, file_path: str) -> None:
        """Save PolygonSetLibrary to an XML file."""
        root = PolygonConfigIO._build_xml(library)
        tree = etree.ElementTree(root)
        tree.write(file_path, encoding="UTF-8", xml_declaration=True, pretty_print=True)

    @staticmethod
    def to_string(library: PolygonSetLibrary) -> str:
        """Convert PolygonSetLibrary to XML string."""
        root = PolygonConfigIO._build_xml(library)
        return etree.tostring(root, encoding="unicode", pretty_print=True)

    @staticmethod
    def _parse_config(root: etree._Element) -> PolygonSetLibrary:
        """Parse PolygonSetLibrary from XML element."""
        # Find the library element
        lib_elem = root.find("PolygonSetLibrary")
        if lib_elem is None:
            # Root might be the library itself
            lib_elem = root if root.tag == "PolygonSetLibrary" else root

        name = lib_elem.get("name", "MainLibrary")
        library = PolygonSetLibrary(name=name)

        # Parse polygon sets
        for ps_elem in lib_elem.findall("PolygonSet"):
            polygon_set = PolygonConfigIO._parse_polygon_set(ps_elem)
            library.add_polygon_set(polygon_set)

        return library

    @staticmethod
    def _parse_polygon_set(elem: etree._Element) -> PolygonSetDef:
        """Parse a PolygonSetDef from XML element."""
        name = elem.get("name", "Untitled")

        # Check for file source
        source_elem = elem.find("Source")
        if source_elem is not None:
            source_type_str = source_elem.get("type", "file")
            if source_type_str == "file":
                file_source = PolygonConfigIO._parse_file_source(source_elem)
                return PolygonSetDef(
                    name=name,
                    source_type=PolygonSourceType.FILE,
                    file_source=file_source
                )
            elif source_type_str == "regular":
                regular_params = PolygonConfigIO._parse_regular_params(source_elem)
                return PolygonSetDef(
                    name=name,
                    source_type=PolygonSourceType.REGULAR,
                    regular_params=regular_params
                )

        # Default to file source with empty filename
        return PolygonSetDef(
            name=name,
            source_type=PolygonSourceType.FILE,
            file_source=FileSource()
        )

    @staticmethod
    def _parse_file_source(elem: etree._Element) -> FileSource:
        """Parse FileSource from XML element."""
        folder = PolygonConfigIO._get_text(elem, "Folder", "polygonSet")
        filename = PolygonConfigIO._get_text(elem, "Filename", "")

        # Parse polygon type
        poly_type_str = PolygonConfigIO._get_text(elem, "PolygonType", "SPLINE_POLYGON")
        try:
            polygon_type = PolygonType(poly_type_str)
        except ValueError:
            polygon_type = PolygonType.SPLINE_POLYGON

        return FileSource(
            folder=folder,
            filename=filename,
            polygon_type=polygon_type
        )

    @staticmethod
    def _parse_regular_params(elem: etree._Element) -> RegularPolygonParams:
        """Parse RegularPolygonParams from XML element."""
        # Parse positiveSynch boolean
        synch_text = PolygonConfigIO._get_text(elem, "PositiveSynch", "true")
        positive_synch = synch_text.lower() in ("true", "1", "yes")

        return RegularPolygonParams(
            total_points=PolygonConfigIO._get_int(elem, "TotalPoints", 4),
            internal_radius=PolygonConfigIO._get_float(elem, "InternalRadius", 0.5),
            offset=PolygonConfigIO._get_float(elem, "Offset", 0.0),
            scale_x=PolygonConfigIO._get_float(elem, "ScaleX", 1.0),
            scale_y=PolygonConfigIO._get_float(elem, "ScaleY", 1.0),
            rotation_angle=PolygonConfigIO._get_float(elem, "RotationAngle", 0.0),
            trans_x=PolygonConfigIO._get_float(elem, "TransX", 0.5),
            trans_y=PolygonConfigIO._get_float(elem, "TransY", 0.5),
            positive_synch=positive_synch,
            synch_multiplier=PolygonConfigIO._get_float(elem, "SynchMultiplier", 1.0)
        )

    @staticmethod
    def _build_xml(library: PolygonSetLibrary) -> etree._Element:
        """Build XML element from PolygonSetLibrary."""
        root = etree.Element("PolygonConfig", version="1.0")

        lib_elem = etree.SubElement(root, "PolygonSetLibrary", name=library.name)

        for polygon_set in library.polygon_sets:
            ps_elem = etree.SubElement(lib_elem, "PolygonSet", name=polygon_set.name)
            PolygonConfigIO._build_polygon_set(ps_elem, polygon_set)

        return root

    @staticmethod
    def _build_polygon_set(elem: etree._Element, polygon_set: PolygonSetDef) -> None:
        """Build polygon set XML elements."""
        if polygon_set.source_type == PolygonSourceType.FILE and polygon_set.file_source:
            source_elem = etree.SubElement(elem, "Source", type="file")
            PolygonConfigIO._add_element(source_elem, "Folder", polygon_set.file_source.folder)
            PolygonConfigIO._add_element(source_elem, "Filename", polygon_set.file_source.filename)
            PolygonConfigIO._add_element(source_elem, "PolygonType", polygon_set.file_source.polygon_type.value)

        elif polygon_set.source_type == PolygonSourceType.REGULAR and polygon_set.regular_params:
            source_elem = etree.SubElement(elem, "Source", type="regular")
            params = polygon_set.regular_params
            PolygonConfigIO._add_element(source_elem, "TotalPoints", str(params.total_points))
            PolygonConfigIO._add_element(source_elem, "InternalRadius", str(params.internal_radius))
            PolygonConfigIO._add_element(source_elem, "Offset", str(params.offset))
            PolygonConfigIO._add_element(source_elem, "ScaleX", str(params.scale_x))
            PolygonConfigIO._add_element(source_elem, "ScaleY", str(params.scale_y))
            PolygonConfigIO._add_element(source_elem, "RotationAngle", str(params.rotation_angle))
            PolygonConfigIO._add_element(source_elem, "TransX", str(params.trans_x))
            PolygonConfigIO._add_element(source_elem, "TransY", str(params.trans_y))
            PolygonConfigIO._add_element(source_elem, "PositiveSynch", str(params.positive_synch).lower())
            PolygonConfigIO._add_element(source_elem, "SynchMultiplier", str(params.synch_multiplier))

    @staticmethod
    def _add_element(parent: etree._Element, name: str, text: str) -> None:
        """Add a child element with text content."""
        elem = etree.SubElement(parent, name)
        elem.text = text

    @staticmethod
    def _get_text(root: etree._Element, name: str, default: str) -> str:
        """Get text content of child element."""
        elem = root.find(name)
        if elem is not None and elem.text:
            return elem.text.strip()
        return default

    @staticmethod
    def _get_int(root: etree._Element, name: str, default: int) -> int:
        """Get integer value of child element."""
        text = PolygonConfigIO._get_text(root, name, "")
        if text:
            try:
                return int(text)
            except ValueError:
                pass
        return default

    @staticmethod
    def _get_float(root: etree._Element, name: str, default: float) -> float:
        """Get float value of child element."""
        text = PolygonConfigIO._get_text(root, name, "")
        if text:
            try:
                return float(text)
            except ValueError:
                pass
        return default
