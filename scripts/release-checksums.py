#!/usr/bin/env python3
"""Require every requested PiaoPal platform package before writing checksums."""
import argparse
import hashlib
from pathlib import Path
import plistlib
import re


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--directory", type=Path, default=Path("dist"))
    parser.add_argument("--platform", choices=["macos", "all"], default="macos")
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", args.version):
        parser.error("version must look like 0.0.1")
    info_path = Path(__file__).resolve().parent.parent / "Info.plist"
    try:
        with info_path.open("rb") as info_file:
            info = plistlib.load(info_file)
            product_name = info.get("CFBundleName")
    except (OSError, plistlib.InvalidFileException) as error:
        parser.error(f"cannot read macOS product name from {info_path}: {error}")
    if not isinstance(product_name, str) or not product_name.strip() or any(
        character in product_name for character in "/\\\r\n"
    ):
        parser.error("Info.plist must contain a valid CFBundleName")
    if product_name != "PiaoPal":
        parser.error("CFBundleName must be PiaoPal")
    if info.get("CFBundleShortVersionString") != args.version:
        parser.error("version must match Info.plist")
    mac_prefix = f"{product_name}-v{args.version}"
    names = [
        f"{mac_prefix}-macOS-universal.dmg",
        f"{mac_prefix}-macOS-universal.zip",
    ]
    if args.platform == "all":
        names.extend([
            f"{mac_prefix}-Windows-x64.zip",
            f"{mac_prefix}-Windows-arm64.zip",
        ])
    names.sort()
    checksums = []
    for name in names:
        path = args.directory / name
        if not path.is_file() or path.stat().st_size == 0:
            raise SystemExit(f"Missing or empty release artifact: {path}")
        digest = hashlib.sha256()
        with path.open("rb") as artifact:
            for block in iter(lambda: artifact.read(1024 * 1024), b""):
                digest.update(block)
        checksums.append(f"{digest.hexdigest()}  {name}\n")
    manifest = args.directory / "SHA256SUMS.txt"
    manifest.write_text("".join(checksums), encoding="utf-8")
    print(manifest)


if __name__ == "__main__":
    main()
