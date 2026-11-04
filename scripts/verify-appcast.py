"""Reject mismatched release metadata; print the archive signature for Sparkle to verify."""
import base64
import plistlib
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

feed_path, archive_path, plist_path = map(Path, sys.argv[1:])
with plist_path.open("rb") as source:
    info = plistlib.load(source)
sparkle = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
items = ET.parse(feed_path).findall("./channel/item")
assert len(items) == 1, "Expected exactly one release in the update feed"
item = items[0]
version = info["CFBundleShortVersionString"]
for key, expected in {
    "version": info["CFBundleVersion"],
    "shortVersionString": version,
    "minimumSystemVersion": info["LSMinimumSystemVersion"],
    "hardwareRequirements": "arm64",
}.items():
    assert item.findtext(sparkle + key) == expected, f"Incorrect {key} in appcast"
enclosure = item.find("enclosure")
assert enclosure is not None, "Missing update archive"
expected_url = f"https://github.com/notsocj/ledge/releases/download/v{version}/Ledge.dmg"
assert enclosure.get("url") == expected_url, "Incorrect archive URL"
assert int(enclosure.get("length", "0")) == archive_path.stat().st_size, "Incorrect archive size"
signature = enclosure.get(sparkle + "edSignature", "")
assert len(base64.b64decode(signature, validate=True)) == 64, "Missing Ed25519 archive signature"
print(signature)
