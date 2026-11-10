#!/usr/bin/env python3
"""从原创图标母版生成各平台资源，仅缩放和转换像素格式。需安装 Pillow。"""

import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
BRANDING = ROOT / "assets/branding"


def save(image, relative, pixels, *, opaque=False, ico=False):
    target = ROOT / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    resized = image.resize((pixels, pixels), Image.Resampling.LANCZOS)
    if opaque:
        resized = resized.convert("RGB")
    if ico:
        resized.save(target, format="ICO", sizes=[(16, 16), (32, 32), (48, 48)])
    else:
        resized.save(target, format="PNG", optimize=True)


def main():
    source = Image.open(BRANDING / "xianbo-icon-source.png").convert("RGB")
    mac = Image.open(BRANDING / "xianbo-macos-source.png").convert("RGBA")
    save(source, "assets/branding/xianbo-icon.png", 256, opaque=True)
    for platform, image in [("macos", mac), ("ios", source)]:
        directory = Path(platform) / "Runner/Assets.xcassets/AppIcon.appiconset"
        contents = json.loads((ROOT / directory / "Contents.json").read_text())
        for entry in contents["images"]:
            points = float(entry["size"].split("x")[0])
            scale = float(entry["scale"].removesuffix("x"))
            save(image, directory / entry["filename"], round(points * scale), opaque=platform == "ios")
    for density, pixels in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        save(source, f"android/app/src/main/res/mipmap-{density}/ic_launcher.png", pixels, opaque=True)
    for pixels in [192, 512]:
        save(source, f"web/icons/icon-{pixels}.png", pixels, opaque=True)
    save(source, "web/apple-touch-icon.png", 180, opaque=True)
    save(source, "web/favicon.png", 32, opaque=True)
    save(source, "web/favicon.ico", 48, opaque=True, ico=True)
    print("Generated Xianbo macOS, iOS, Android, Web and in-app icons.")


if __name__ == "__main__":
    main()
