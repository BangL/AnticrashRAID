#!/usr/bin/env python3
# Writes lua/text_fields.lua from the RPC definition of the game
# (extracted/settings/network.network_settings): every string / longstring parameter of a
# connection or unit message. Index 1 is self, the first parameter is index 2.
# usage: gen_text_fields.py <network.network_settings> > lua/text_fields.lua
import re
import sys

OBJECTS = {"connection": "ConnectionNetworkHandler", "unit": "UnitNetworkHandler"}

# binary data that is not text: auth tickets and the outfit signature
EXCEPTIONS = {
    "connection": {
        "request_join": {9},
        "join_request_reply": {12},
        "sync_outfit": {4},
    },
}

text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
text = re.sub(r"<!--.*?-->", "", text, flags=re.S)

fields = {name: {} for name in OBJECTS}
for m in re.finditer(r"<message\s+([^>]*?)(/>|>(.*?)</message>)", text, flags=re.S):
    attrs = dict(re.findall(r'(\w+)="([^"]*)"', m.group(1)))
    receiver = attrs.get("receiver")
    if receiver not in OBJECTS:
        continue
    types = re.findall(r'<param\s+type="(\w+)"', m.group(3) or "")
    skip = EXCEPTIONS.get(receiver, {}).get(attrs["name"], set())
    idx = [i + 2 for i, t in enumerate(types) if t in ("string", "longstring") and i + 2 not in skip]
    if idx:
        fields[receiver][attrs["name"]] = idx

out = []
for receiver, obj in OBJECTS.items():
    rows = ["\t%s = { %s }" % (n, ", ".join(map(str, i))) for n, i in sorted(fields[receiver].items())]
    out.append("Anticrash.objects.%s.text_fields = {\n%s\n}" % (obj, ",\n".join(rows)))
print("\n".join(out))
