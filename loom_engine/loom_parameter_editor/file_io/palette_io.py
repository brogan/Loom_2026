"""
I/O for standalone palette files stored in a project's palettes/ directory.
"""
import os
from lxml import etree
from models.rendering import Color


class ColorPaletteIO:
    @classmethod
    def save(cls, colors: list[Color], path: str) -> None:
        name = _name_from_path(path, "_colors")
        root = etree.Element("ColorPalette", name=name)
        for c in colors:
            e = etree.SubElement(root, "PaletteColor")
            e.set("r", str(c.r))
            e.set("g", str(c.g))
            e.set("b", str(c.b))
            e.set("a", str(c.a))
        etree.ElementTree(root).write(
            path, pretty_print=True, xml_declaration=True, encoding="UTF-8"
        )

    @classmethod
    def load(cls, path: str) -> list[Color]:
        tree = etree.parse(path)
        root = tree.getroot()
        return [
            Color(
                r=int(e.get("r", "0")),
                g=int(e.get("g", "0")),
                b=int(e.get("b", "0")),
                a=int(e.get("a", "255")),
            )
            for e in root.findall("PaletteColor")
        ]


class SizePaletteIO:
    @classmethod
    def save(cls, values: list[float], path: str) -> None:
        name = _name_from_path(path, "_sizes")
        root = etree.Element("SizePalette", name=name)
        for v in values:
            etree.SubElement(root, "PaletteEntry").text = str(v)
        etree.ElementTree(root).write(
            path, pretty_print=True, xml_declaration=True, encoding="UTF-8"
        )

    @classmethod
    def load(cls, path: str) -> list[float]:
        tree = etree.parse(path)
        root = tree.getroot()
        return [
            float(e.text.strip())
            for e in root.findall("PaletteEntry")
            if e.text
        ]


def _name_from_path(path: str, suffix: str) -> str:
    base = os.path.basename(path)
    expected_tail = suffix + ".xml"
    if base.endswith(expected_tail):
        return base[: -len(expected_tail)]
    return base
