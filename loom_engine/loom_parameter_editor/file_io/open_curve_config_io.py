"""
XML I/O for OpenCurveConfig.
Reads and writes curves.xml files.
"""
from lxml import etree
from models.open_curve_config import OpenCurveDef, OpenCurveSetLibrary, OpenCurveSourceType
from models.polygon_config import FileSource


class OpenCurveConfigIO:
    """Read and write open curve configuration XML files."""

    @staticmethod
    def load(file_path: str) -> OpenCurveSetLibrary:
        tree = etree.parse(file_path)
        root = tree.getroot()
        return OpenCurveConfigIO._parse_config(root)

    @staticmethod
    def save(library: OpenCurveSetLibrary, file_path: str) -> None:
        root = OpenCurveConfigIO._build_xml(library)
        tree = etree.ElementTree(root)
        tree.write(file_path, encoding="UTF-8", xml_declaration=True, pretty_print=True)

    @staticmethod
    def to_string(library: OpenCurveSetLibrary) -> str:
        root = OpenCurveConfigIO._build_xml(library)
        return etree.tostring(root, encoding="unicode", pretty_print=True)

    @staticmethod
    def _parse_config(root: etree._Element) -> OpenCurveSetLibrary:
        lib_elem = root.find("OpenCurveSetLibrary")
        if lib_elem is None:
            lib_elem = root if root.tag == "OpenCurveSetLibrary" else root

        name = lib_elem.get("name", "MainLibrary")
        library = OpenCurveSetLibrary(name=name)

        for cs_elem in lib_elem.findall("OpenCurveSet"):
            curve_set = OpenCurveConfigIO._parse_curve_set(cs_elem)
            library.add_curve_set(curve_set)

        return library

    @staticmethod
    def _parse_curve_set(elem: etree._Element) -> OpenCurveDef:
        name = elem.get("name", "Untitled")
        source_elem = elem.find("Source")
        if source_elem is not None and source_elem.get("type", "file") == "file":
            folder_elem = source_elem.find("Folder")
            filename_elem = source_elem.find("Filename")
            folder = folder_elem.text.strip() if folder_elem is not None and folder_elem.text else "curveSets"
            filename = filename_elem.text.strip() if filename_elem is not None and filename_elem.text else ""
            file_source = FileSource(folder=folder, filename=filename)
            return OpenCurveDef(name=name, source_type=OpenCurveSourceType.FILE, file_source=file_source)

        return OpenCurveDef(name=name)

    @staticmethod
    def _build_xml(library: OpenCurveSetLibrary) -> etree._Element:
        root = etree.Element("CurveConfig", version="1.0")
        lib_elem = etree.SubElement(root, "OpenCurveSetLibrary", name=library.name)
        for curve_set in library.curve_sets:
            cs_elem = etree.SubElement(lib_elem, "OpenCurveSet", name=curve_set.name)
            if curve_set.file_source is not None:
                source_elem = etree.SubElement(cs_elem, "Source", type="file")
                folder_elem = etree.SubElement(source_elem, "Folder")
                folder_elem.text = curve_set.file_source.folder or "curveSets"
                filename_elem = etree.SubElement(source_elem, "Filename")
                filename_elem.text = curve_set.file_source.filename or ""
        return root
