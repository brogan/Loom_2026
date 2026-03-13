"""
XML I/O for PointConfig.
Reads and writes points.xml files.
"""
from lxml import etree
from models.point_config import PointSetDef, PointSetLibrary, PointSourceType
from models.polygon_config import FileSource


class PointConfigIO:
    """Read and write point set configuration XML files."""

    @staticmethod
    def load(file_path: str) -> PointSetLibrary:
        tree = etree.parse(file_path)
        root = tree.getroot()
        return PointConfigIO._parse_config(root)

    @staticmethod
    def save(library: PointSetLibrary, file_path: str) -> None:
        root = PointConfigIO._build_xml(library)
        tree = etree.ElementTree(root)
        tree.write(file_path, encoding="UTF-8", xml_declaration=True, pretty_print=True)

    @staticmethod
    def to_string(library: PointSetLibrary) -> str:
        root = PointConfigIO._build_xml(library)
        return etree.tostring(root, encoding="unicode", pretty_print=True)

    @staticmethod
    def _parse_config(root: etree._Element) -> PointSetLibrary:
        lib_elem = root.find("PointSetLibrary")
        if lib_elem is None:
            lib_elem = root if root.tag == "PointSetLibrary" else root

        name = lib_elem.get("name", "MainLibrary")
        library = PointSetLibrary(name=name)

        for ps_elem in lib_elem.findall("PointSet"):
            ps = PointConfigIO._parse_point_set(ps_elem)
            library.add_point_set(ps)

        return library

    @staticmethod
    def _parse_point_set(elem: etree._Element) -> PointSetDef:
        name = elem.get("name", "Untitled")
        source_elem = elem.find("Source")
        if source_elem is not None and source_elem.get("type", "file") == "file":
            folder_elem = source_elem.find("Folder")
            filename_elem = source_elem.find("Filename")
            folder = folder_elem.text.strip() if folder_elem is not None and folder_elem.text else "pointSets"
            filename = filename_elem.text.strip() if filename_elem is not None and filename_elem.text else ""
            file_source = FileSource(folder=folder, filename=filename)
            return PointSetDef(name=name, source_type=PointSourceType.FILE, file_source=file_source)
        return PointSetDef(name=name)

    @staticmethod
    def _build_xml(library: PointSetLibrary) -> etree._Element:
        root = etree.Element("PointConfig", version="1.0")
        lib_elem = etree.SubElement(root, "PointSetLibrary", name=library.name)
        for ps in library.point_sets:
            ps_elem = etree.SubElement(lib_elem, "PointSet", name=ps.name)
            if ps.file_source is not None:
                source_elem = etree.SubElement(ps_elem, "Source", type="file")
                folder_elem = etree.SubElement(source_elem, "Folder")
                folder_elem.text = ps.file_source.folder or "pointSets"
                filename_elem = etree.SubElement(source_elem, "Filename")
                filename_elem.text = ps.file_source.filename or ""
        return root
