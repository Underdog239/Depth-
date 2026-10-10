#!/usr/bin/env python3
"""Check script-relative require targets in a Rojo-built .rbxlx place."""
import re
import sys
import xml.etree.ElementTree as ET


def validate(path):
    root = ET.parse(path).getroot()
    parents = {child: item for item in root.iter() for child in item if child.tag == "Item"}
    checked = 0
    for item in root.iter("Item"):
        source = item.find("./Properties/*[@name='Source']")
        if source is None:
            continue
        for match in re.finditer(r"require\(script((?:\.[A-Za-z0-9_]+)+)\)", source.text or ""):
            target = item
            for part in match.group(1).split(".")[1:]:
                if part == "Parent":
                    target = parents.get(target)
                else:
                    target = next((c for c in target.findall("Item")
                                   if c.findtext("./Properties/string[@name='Name']") == part), None)
                if target is None:
                    raise ValueError("Unresolved " + match.group(0) + " in " + item.findtext("./Properties/string[@name='Name']"))
            if target.attrib.get("class") != "ModuleScript":
                raise ValueError("Require target is not a ModuleScript: " + match.group(0))
            checked += 1
    if checked == 0:
        raise ValueError("No script requires found")
    print(f"Validated {checked} script-relative requires in the built place")


if __name__ == "__main__":
    validate(sys.argv[1])
