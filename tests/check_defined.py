"""Fail if the addon calls AW.<name>(...) for a function no file defines (that is a runtime error in game)."""
import glob, re, sys

src = {f: open(f, encoding="utf-8").read() for f in glob.glob("*.lua")}
defined = set()
for text in src.values():
    defined.update(m.group(1) for m in re.finditer(r"\bAW\.([A-Za-z_]\w*)\s*=", text))
    defined.update(m.group(1) for m in re.finditer(r"function\s+AW\.([A-Za-z_]\w*)", text))
missing = {}
for f, text in src.items():
    for m in re.finditer(r"\bAW\.([A-Za-z_]\w*)\s*\(", text):
        if m.group(1) not in defined:
            missing.setdefault(m.group(1), set()).add(f)
if missing:
    for name, files in sorted(missing.items()):
        print("undefined function AW.%s called from %s" % (name, ", ".join(sorted(files))))
    sys.exit(1)
print("all AW.* calls are defined")
