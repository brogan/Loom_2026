"""
XML I/O for OvalConfig.
Reads and writes ovals.xml files.
"""
from lxml import etree
from models.oval_config import OvalSetDef, OvalSetLibrary, OvalSourceType
from models.polygon_config import FileSource


class OvalConfigIO:
    """Read and write oval set configuration XML files."""

    @staticmethod
    def load(file_path: str) -> OvalSetLibrary:
        tree = etree.parse(file_path)
        root = tree.getroot()
        return OvalConfigIO._parse_config(root)

    @staticmethod
    def save(library: OvalSetLibrary, file_path: str) -> None:
        root = OvalConfigIO._build_xml(library)
        tree = etree.ElementTree(root)
        tree.write(file_path, encoding="UTF-8", xml_declaration=True, pretty_print=True)

    @staticmethod
    def to_string(library: OvalSetLibrary) -> str:
        root = OvalConfigIO._build_xml(library)
        return etree.tostring(root, encoding="unicode", pretty_print=True)

    @staticmethod
    def _parse_config(root: etree._Element) -> OvalSetLibrary:
        lib_elem = root.find("OvalSetLibrary")
        if lib_elem is None:
            lib_elem = root if root.tag == "OvalSetLibrary" else root

        name = lib_elem.get("name", "MainLibrary")
        library = OvalSetLibrary(name=name)

        for os_elem in lib_elem.findall("OvalSet"):
            os = OvalConfigIO._parse_oval_set(os_elem)
            library.add_oval_set(os)

        return library

    @staticmethod
    def _parse_oval_set(elem: etree._Element) -> OvalSetDef:
        name = elem.get("name", "Untitled")
        source_elem = elem.find("Source")
        if source_elem is not None and source_elem.get("type", "file") == "file":
            folder_elem = source_elem.find("Folder")
            filename_elem = source_elem.find("Filename")
            folder = folder_elem.text.strip() if folder_elem is not None and folder_elem.text else "ovalSets"
            filename = filename_elem.text.strip() if filename_elem is not None and filename_elem.text else ""
            file_source = FileSource(folder=folder, filename=filename)
            return OvalSetDef(name=name, source_type=OvalSourceType.FILE, file_source=file_source)
        return OvalSetDef(name=name)

    @staticmethod
    def _build_xml(library: OvalSetLibrary) -> etree._Element:
        root = etree.Element("OvalConfig", version="1.0")
        lib_elem = etree.SubElement(root, "OvalSetLibrary", name=library.name)
        for os in library.oval_sets:
            os_elem = etree.SubElement(lib_elem, "OvalSet", name=os.name)
            if os.file_source is not None:
                source_elem = etree.SubElement(os_elem, "Source", type="file")
                folder_elem = etree.SubElement(source_elem, "Folder")
                folder_elem.text = os.file_source.folder or "ovalSets"
                filename_elem = etree.SubElement(source_elem, "Filename")
                filename_elem.text = os.file_source.filename or ""
        return root
