#!/usr/bin/env python3
"""Check client-only layout and static require targets in a Rojo-built place."""
import re
import sys
import xml.etree.ElementTree as ET


def validate(path):
    root = ET.parse(path).getroot()
    parents = {child: item for item in root.iter() for child in item if child.tag == "Item"}
    checked = 0
    replicated = root.find("Item[@class='ReplicatedStorage']")
    if replicated is None:
        raise ValueError("Missing ReplicatedStorage")
    forbidden = {"Script", "ServerScriptService", "RemoteFunction", "RemoteEvent", "UnreliableRemoteEvent"}
    clients = 0
    for item in root.iter("Item"):
        if item.attrib.get("class") in forbidden:
            raise ValueError("Server/network instance in client-only build: " + item.attrib["class"])
        if item.attrib.get("class") == "LocalScript":
            clients += 1
        source = item.find("./Properties/*[@name='Source']")
        if source is None:
            continue
        text = source.text or ""
        text = text.replace('game:GetService("ReplicatedStorage").Shared', 'ReplicatedStorage.Shared')
        if re.search(r':\s*(?:InvokeServer|FireServer|GetDataStore)\s*\(', text):
            raise ValueError("Server API call in client-only source")
        for match in re.finditer(r"require\((script|ReplicatedStorage)((?:\.[A-Za-z0-9_]+)+)\)", text):
            target = item if match.group(1) == "script" else replicated
            for part in match.group(2).split(".")[1:]:
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
    if clients != 1:
        raise ValueError("Expected exactly one client bootstrap")
    if checked == 0:
        raise ValueError("No script requires found")
    print(f"Validated {checked} static requires; client-only place has one LocalScript and no server/remotes")


if __name__ == "__main__":
    validate(sys.argv[1])
