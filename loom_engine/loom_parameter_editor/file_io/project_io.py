"""
XML I/O for project manifest files.
"""
from lxml import etree
from datetime import datetime
from models.project import Project, ProjectFile


class ProjectIO:
    """Handles reading and writing project.xml files."""

    VERSION = "1.0"
    DATETIME_FORMAT = "%Y-%m-%dT%H:%M:%S"

    @classmethod
    def load(cls, file_path: str) -> Project:
        """Load a Project from an XML file."""
        tree = etree.parse(file_path)
        root = tree.getroot()

        if root.tag != "LoomProject":
            raise ValueError(f"Expected LoomProject root element, got {root.tag}")

        project = Project()
        project.version = root.get("version", cls.VERSION)

        name_elem = root.find("Name")
        if name_elem is not None and name_elem.text:
            project.name = name_elem.text.strip()

        desc_elem = root.find("Description")
        if desc_elem is not None and desc_elem.text:
            project.description = desc_elem.text.strip()

        created_elem = root.find("Created")
        if created_elem is not None and created_elem.text:
            try:
                project.created = datetime.strptime(created_elem.text.strip(), cls.DATETIME_FORMAT)
            except ValueError:
                pass  # Keep default

        modified_elem = root.find("Modified")
        if modified_elem is not None and modified_elem.text:
            try:
                project.modified = datetime.strptime(modified_elem.text.strip(), cls.DATETIME_FORMAT)
            except ValueError:
                pass  # Keep default

        files_elem = root.find("Files")
        if files_elem is not None:
            for file_elem in files_elem.findall("File"):
                domain = file_elem.get("domain", "")
                path = file_elem.get("path", "")
                if domain and path:
                    project.files.append(ProjectFile(domain=domain, path=path))

        return project

    @classmethod
    def save(cls, project: Project, file_path: str) -> None:
        """Save a Project to an XML file."""
        root = etree.Element("LoomProject", version=project.version)

        etree.SubElement(root, "Name").text = project.name
        etree.SubElement(root, "Description").text = project.description
        etree.SubElement(root, "Created").text = project.created.strftime(cls.DATETIME_FORMAT)
        etree.SubElement(root, "Modified").text = project.modified.strftime(cls.DATETIME_FORMAT)

        files_elem = etree.SubElement(root, "Files")
        for pf in project.files:
            file_elem = etree.SubElement(files_elem, "File")
            file_elem.set("domain", pf.domain)
            file_elem.set("path", pf.path)

        tree = etree.ElementTree(root)
        tree.write(file_path, pretty_print=True, xml_declaration=True, encoding="UTF-8")

    @classmethod
    def create_new(cls, name: str = "New Project") -> Project:
        """Create a new project with default rendering file."""
        project = Project(name=name)
        project.add_file("rendering", "rendering.xml")
        return project
