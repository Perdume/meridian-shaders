"""Builds Meridian's two packs from one source, each with only the files its manifest uses:

    pack/            Meridian: the engine's shadow map ([shadow]); Horizon Nightly 2026-11-01 and later
    pack/ + compat/  Meridian (screen-space shadows): Horizon 0.2.97 and older Nightlies, which reject
                     [shadow]; compat/'s files replace pack/'s

    python tools/build_packs.py [OUT]        default OUT: dist/packs
        OUT/meridian/  OUT/meridian_compat/        ready for `horizon-shader check` and `pack`
"""
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EXTRAS = ("README.md", "LICENSE", "icon.png")


def used_files(manifest: str) -> list[str]:
    files = re.findall(r'^file = "([^"]+)"', manifest, flags=re.M)
    # `shared = [...]` and each stage's `files = [...]`, and [[textures]] files (PNGs).
    for listed in re.findall(r"^(?:shared|files) = \[([^\]]*)\]", manifest, flags=re.M):
        files += re.findall(r'"([^"]+)"', listed)
    return sorted(set(files))


def build(name: str, layers: list[Path], out: Path) -> None:
    def source(rel: str) -> Path:
        for layer in reversed(layers):
            if (layer / rel).is_file():
                return layer / rel
        raise SystemExit(f"{name}: {rel} is in no layer")

    manifest = source("horizon-shaders.toml").read_text(encoding="utf-8")
    dest = out / name
    shutil.rmtree(dest, ignore_errors=True)
    for rel in ["horizon-shaders.toml", *used_files(manifest), *EXTRAS]:
        try:
            src = source(rel)
        except SystemExit:
            if rel in EXTRAS:
                continue
            raise
        (dest / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dest / rel)
    print(f"{name}: {sum(1 for p in dest.rglob('*') if p.is_file())} files in {dest.relative_to(ROOT)}")


def main() -> int:
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "dist" / "packs"
    build("meridian", [ROOT / "pack"], out)
    build("meridian_compat", [ROOT / "pack", ROOT / "compat"], out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
