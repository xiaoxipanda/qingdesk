#!/usr/bin/env python3
"""Package an app as a standard ZIP, without resource-fork sidecar files."""
import argparse
from pathlib import Path
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument("app", type=Path)
parser.add_argument("output", type=Path)
args = parser.parse_args()
app = args.app.resolve()
if not (app / "Contents/Info.plist").is_file():
    parser.error("Expected a complete .app bundle")
args.output.parent.mkdir(parents=True, exist_ok=True)
temporary = args.output.with_suffix(".zip.partial")
try:
    with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED,
                         compresslevel=6, allowZip64=False) as archive:
        for path in [app, *sorted(app.rglob("*"))]:
            if path.name == ".DS_Store" or path.name.startswith("._"):
                continue
            if path.is_symlink():
                raise ValueError(f"Unexpected symlink in this standalone app: {path}")
            archive.write(path, path.relative_to(app.parent).as_posix())
    with zipfile.ZipFile(temporary) as archive:
        if archive.testzip() is not None:
            raise ValueError("ZIP integrity check failed")
    temporary.replace(args.output)
finally:
    temporary.unlink(missing_ok=True)
print(f"Packaged: {args.output.resolve()}")
