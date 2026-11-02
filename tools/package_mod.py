"""Packs the native mod in mod/ into dist/<id>-<version>.hnmod: horizon-native.json and
mixins/<id>/ (the .rs and .toml files only), in path order with fixed dates, so the same
sources always give the same bytes.

    python tools/package_mod.py
"""
import json
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MOD = ROOT / "mod"


def main() -> int:
    meta = json.loads((MOD / "horizon-native.json").read_text(encoding="utf-8"))
    mod_id, version = meta["id"], meta["version"]
    bundle = MOD / "mixins" / mod_id
    toml = (bundle / "horizon-mixin.toml").read_text(encoding="utf-8")
    if f'version = "{version}"' not in toml or f'id = "{mod_id}"' not in toml:
        print("horizon-native.json and horizon-mixin.toml disagree on id or version")
        return 1
    files = sorted(p for p in bundle.rglob("*") if p.is_file() and p.suffix in (".rs", ".toml"))
    out = ROOT / "dist" / f"{mod_id}-{version}.hnmod"
    out.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        entries = [("horizon-native.json", MOD / "horizon-native.json")]
        entries += [(p.relative_to(MOD).as_posix(), p) for p in files]
        for name, path in entries:
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            z.writestr(info, path.read_bytes())
    print(f"wrote {out.relative_to(ROOT)} ({len(entries)} files)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
