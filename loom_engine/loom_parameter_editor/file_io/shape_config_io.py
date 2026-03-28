"""
Shape configuration XML I/O.

Handles reading and writing shapes.xml files.
"""
from lxml import etree
from typing import List
from models.shape_config import (
    ShapeLibrary, ShapeSet, ShapeDef, Vector2D,
    ShapeSourceType, Shape3DType
)


class ShapeConfigIO:
    """Read/write shape configuration XML files."""

    @staticmethod
    def load(file_path: str) -> ShapeLibrary:
        """Load a ShapeLibrary from an XML file."""
        try:
            tree = etree.parse(file_path)
            root = tree.getroot()
            return ShapeConfigIO._parse_config(root)
        except Exception as e:
            print(f"Error loading shape config from {file_path}: {e}")
            return ShapeLibrary()

    @staticmethod
    def save(library: ShapeLibrary, file_path: str) -> None:
        """Save a ShapeLibrary to an XML file."""
        root = ShapeConfigIO._build_xml(library)
        tree = etree.ElementTree(root)
        tree.write(file_path, pretty_print=True, xml_declaration=True, encoding="UTF-8")

    @staticmethod
    def _parse_config(root: etree._Element) -> ShapeLibrary:
        """Parse the root ShapeConfig element."""
        library = ShapeLibrary()

        # Find ShapeLibrary element
        lib_elem = root.find("ShapeLibrary")
        if lib_elem is not None:
            library.name = lib_elem.get("name", "MainLibrary")

            # Parse each ShapeSet
            for set_elem in lib_elem.findall("ShapeSet"):
                shape_set = ShapeConfigIO._parse_shape_set(set_elem)
                library.add(shape_set)

            # Also check for Shape elements directly under library (flat structure)
            for shape_elem in lib_elem.findall("Shape"):
                # Create a default set if needed
                if not library.shape_sets:
                    library.add(ShapeSet(name="default"))
                shape = ShapeConfigIO._parse_shape(shape_elem)
                library.shape_sets[0].add(shape)

        return library

    @staticmethod
    def _parse_shape_set(elem: etree._Element) -> ShapeSet:
        """Parse a ShapeSet element."""
        shape_set = ShapeSet(name=elem.get("name", "default"))

        for shape_elem in elem.findall("Shape"):
            shape = ShapeConfigIO._parse_shape(shape_elem)
            shape_set.add(shape)

        return shape_set

    @staticmethod
    def _parse_shape(elem: etree._Element) -> ShapeDef:
        """Parse a Shape element."""
        shape = ShapeDef(name=elem.get("name", "default"))

        # Parse source type
        source_elem = elem.find("Source")
        if source_elem is not None:
            type_str = source_elem.get("type", "POLYGON_SET").upper()
            shape.source_type = ShapeConfigIO._parse_source_type(type_str)

            if shape.source_type == ShapeSourceType.POLYGON_SET:
                shape.polygon_set_name = source_elem.get("polygonSet", "")
            elif shape.source_type == ShapeSourceType.REGULAR_POLYGON:
                shape.regular_polygon_sides = int(source_elem.get("sides", "4"))
            elif shape.source_type == ShapeSourceType.INLINE_POINTS:
                shape.inline_points = ShapeConfigIO._parse_points(source_elem)
            elif shape.source_type == ShapeSourceType.OPEN_CURVE_SET:
                shape.open_curve_set_name = source_elem.get("openCurveSet", "")
            elif shape.source_type == ShapeSourceType.POINT_SET:
                shape.point_set_name = source_elem.get("pointSet", "")
            elif shape.source_type == ShapeSourceType.OVAL_SET:
                shape.oval_set_name = source_elem.get("ovalSet", "")

        # Parse subdivision reference
        subdiv_elem = elem.find("SubdivisionParamsSet")
        if subdiv_elem is not None:
            shape.subdivision_params_set_name = subdiv_elem.get("name", "")

        # Parse 3D type
        type_3d_elem = elem.find("Shape3D")
        if type_3d_elem is not None:
            type_str = type_3d_elem.get("type", "NONE").upper()
            shape.shape_3d_type = ShapeConfigIO._parse_3d_type(type_str)
            shape.shape_3d_param1 = int(type_3d_elem.get("param1", "4"))
            shape.shape_3d_param2 = int(type_3d_elem.get("param2", "4"))
            shape.shape_3d_param3 = int(type_3d_elem.get("param3", "4"))

        # Parse transform
        transform_elem = elem.find("Transform")
        if transform_elem is not None:
            trans_elem = transform_elem.find("Translation")
            if trans_elem is not None:
                shape.translate_x = float(trans_elem.get("x", "0"))
                shape.translate_y = float(trans_elem.get("y", "0"))

            scale_elem = transform_elem.find("Scale")
            if scale_elem is not None:
                shape.scale_x = float(scale_elem.get("x", "1"))
                shape.scale_y = float(scale_elem.get("y", "1"))

            rot_elem = transform_elem.find("Rotation")
            if rot_elem is not None:
                shape.rotation = float(rot_elem.get("angle", "0"))

        return shape

    @staticmethod
    def _parse_points(elem: etree._Element) -> List[Vector2D]:
        """Parse inline points."""
        points = []
        for point_elem in elem.findall("Point"):
            x = float(point_elem.get("x", "0"))
            y = float(point_elem.get("y", "0"))
            points.append(Vector2D(x, y))
        return points

    @staticmethod
    def _parse_source_type(type_str: str) -> ShapeSourceType:
        """Parse source type string to enum."""
        mapping = {
            "POLYGON_SET": ShapeSourceType.POLYGON_SET,
            "REGULAR_POLYGON": ShapeSourceType.REGULAR_POLYGON,
            "INLINE_POINTS": ShapeSourceType.INLINE_POINTS,
            "OPENCURVESET": ShapeSourceType.OPEN_CURVE_SET,
            "OPEN_CURVE_SET": ShapeSourceType.OPEN_CURVE_SET,
            "POINTSET": ShapeSourceType.POINT_SET,
            "POINT_SET": ShapeSourceType.POINT_SET,
            "OVALSET": ShapeSourceType.OVAL_SET,
            "OVAL_SET": ShapeSourceType.OVAL_SET,
        }
        return mapping.get(type_str, ShapeSourceType.POLYGON_SET)

    @staticmethod
    def _parse_3d_type(type_str: str) -> Shape3DType:
        """Parse 3D type string to enum."""
        mapping = {
            "NONE": Shape3DType.NONE,
            "CRYSTAL": Shape3DType.CRYSTAL,
            "RECT_PRISM": Shape3DType.RECT_PRISM,
            "EXTRUSION": Shape3DType.EXTRUSION,
            "GRID_PLANE": Shape3DType.GRID_PLANE,
            "GRID_BLOCK": Shape3DType.GRID_BLOCK,
        }
        return mapping.get(type_str, Shape3DType.NONE)

    @staticmethod
    def _build_xml(library: ShapeLibrary) -> etree._Element:
        """Build XML from a ShapeLibrary."""
        root = etree.Element("ShapeConfig", version="1.0")

        lib_elem = etree.SubElement(root, "ShapeLibrary", name=library.name)

        for shape_set in library.shape_sets:
            set_elem = etree.SubElement(lib_elem, "ShapeSet", name=shape_set.name)

            for shape in shape_set.shapes:
                ShapeConfigIO._build_shape_xml(set_elem, shape)

        return root

    @staticmethod
    def _build_shape_xml(parent: etree._Element, shape: ShapeDef) -> None:
        """Build XML for a single shape."""
        shape_elem = etree.SubElement(parent, "Shape", name=shape.name)

        # Source
        if shape.source_type == ShapeSourceType.OPEN_CURVE_SET:
            source_elem = etree.SubElement(shape_elem, "Source", type="openCurveSet")
            source_elem.set("openCurveSet", shape.open_curve_set_name)
        elif shape.source_type == ShapeSourceType.POINT_SET:
            source_elem = etree.SubElement(shape_elem, "Source", type="pointSet")
            source_elem.set("pointSet", shape.point_set_name)
        elif shape.source_type == ShapeSourceType.OVAL_SET:
            source_elem = etree.SubElement(shape_elem, "Source", type="ovalSet")
            source_elem.set("ovalSet", shape.oval_set_name)
        else:
            source_elem = etree.SubElement(shape_elem, "Source",
                                           type=shape.source_type.name)
            if shape.source_type == ShapeSourceType.POLYGON_SET:
                source_elem.set("polygonSet", shape.polygon_set_name)
            elif shape.source_type == ShapeSourceType.REGULAR_POLYGON:
                source_elem.set("sides", str(shape.regular_polygon_sides))
            elif shape.source_type == ShapeSourceType.INLINE_POINTS:
                for point in shape.inline_points:
                    etree.SubElement(source_elem, "Point",
                                    x=str(point.x), y=str(point.y))

        # Subdivision reference
        if shape.subdivision_params_set_name:
            etree.SubElement(shape_elem, "SubdivisionParamsSet",
                            name=shape.subdivision_params_set_name)

        # 3D type
        if shape.shape_3d_type != Shape3DType.NONE:
            etree.SubElement(shape_elem, "Shape3D",
                            type=shape.shape_3d_type.name,
                            param1=str(shape.shape_3d_param1),
                            param2=str(shape.shape_3d_param2),
                            param3=str(shape.shape_3d_param3))

        # Transform
        if (shape.translate_x != 0 or shape.translate_y != 0 or
            shape.scale_x != 1 or shape.scale_y != 1 or shape.rotation != 0):
            transform_elem = etree.SubElement(shape_elem, "Transform")
            etree.SubElement(transform_elem, "Translation",
                            x=str(shape.translate_x), y=str(shape.translate_y))
            etree.SubElement(transform_elem, "Scale",
                            x=str(shape.scale_x), y=str(shape.scale_y))
            etree.SubElement(transform_elem, "Rotation",
                            angle=str(shape.rotation))
