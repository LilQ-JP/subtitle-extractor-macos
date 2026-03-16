#!/usr/bin/env python3

import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw


CANVAS_SIZE = 1024
BACKGROUND_INSET = 48
BACKGROUND_RADIUS = 220


def parse_color_spec(value: str) -> tuple[int, int, int, int]:
    space, numbers = value.split(":", 1)
    components = [float(item) for item in numbers.split(",")]

    if space == "gray":
        gray = int(round(components[0] * 255))
        alpha = int(round((components[1] if len(components) > 1 else 1.0) * 255))
        return gray, gray, gray, alpha

    if len(components) == 3:
        components.append(1.0)
    return tuple(int(round(component * 255)) for component in components)


def lighten(color: tuple[int, int, int], factor: float) -> tuple[int, int, int]:
    return tuple(
        int(round(channel + (255 - channel) * factor))
        for channel in color
    )


def darken(color: tuple[int, int, int], factor: float) -> tuple[int, int, int]:
    return tuple(
        int(round(channel * (1.0 - factor)))
        for channel in color
    )


def make_background(fill_value: str) -> Image.Image:
    base_rgba = parse_color_spec(fill_value)
    base_rgb = base_rgba[:3]
    start = lighten(base_rgb, 0.12)
    end = darken(base_rgb, 0.10)

    gradient = Image.new("RGBA", (CANVAS_SIZE, CANVAS_SIZE))
    pixels = gradient.load()
    scale = float((CANVAS_SIZE - 1) * 2)
    for y in range(CANVAS_SIZE):
        for x in range(CANVAS_SIZE):
            mix = (x + y) / scale
            color = tuple(
                int(round(start[index] * (1.0 - mix) + end[index] * mix))
                for index in range(3)
            )
            pixels[x, y] = (*color, 255)

    rounded_mask = Image.new("L", (CANVAS_SIZE, CANVAS_SIZE), 0)
    draw = ImageDraw.Draw(rounded_mask)
    draw.rounded_rectangle(
        (
            BACKGROUND_INSET,
            BACKGROUND_INSET,
            CANVAS_SIZE - BACKGROUND_INSET,
            CANVAS_SIZE - BACKGROUND_INSET,
        ),
        radius=BACKGROUND_RADIUS,
        fill=255,
    )

    background = Image.new("RGBA", (CANVAS_SIZE, CANVAS_SIZE), (0, 0, 0, 0))
    background.alpha_composite(Image.composite(gradient, background, rounded_mask))
    return background


def recolor_layer(image: Image.Image, layer: dict) -> Image.Image:
    fill_specializations = layer.get("fill-specializations") or []
    fill_value = None
    for specialization in fill_specializations:
        value = specialization.get("value", {})
        solid = value.get("solid") if isinstance(value, dict) else None
        if solid:
            fill_value = solid
            break

    if not fill_value:
        return image

    color = parse_color_spec(fill_value)
    alpha = image.getchannel("A")
    colored = Image.new("RGBA", image.size, color)
    colored.putalpha(alpha)
    return colored


def render_icon(icon_directory: Path, output_path: Path) -> None:
    icon_payload = json.loads((icon_directory / "icon.json").read_text(encoding="utf-8"))
    background_fill = icon_payload.get("fill", {}).get("automatic-gradient", "extended-srgb:0.00000,0.53333,1.00000,1.00000")
    canvas = make_background(background_fill)
    asset_directory = icon_directory / "Assets"

    groups = icon_payload.get("groups") or []
    if not groups:
        raise SystemExit("No groups found in icon.json")

    for layer in groups[0].get("layers", []):
        if layer.get("hidden"):
            continue

        asset_name = layer.get("image-name")
        if not asset_name:
            continue

        image = Image.open(asset_directory / asset_name).convert("RGBA")
        image = recolor_layer(image, layer)

        translation_x, translation_y = layer.get("position", {}).get("translation-in-points", [0, 0])
        origin_x = int(round((CANVAS_SIZE - image.width) / 2 + translation_x))
        origin_y = int(round((CANVAS_SIZE - image.height) / 2 + translation_y))
        canvas.alpha_composite(image, (origin_x, origin_y))

    output_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(output_path)


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("Usage: render_icon_composer_icon.py <input.icon> <output.png>")

    input_path = Path(sys.argv[1]).expanduser().resolve()
    output_path = Path(sys.argv[2]).expanduser().resolve()
    render_icon(input_path, output_path)


if __name__ == "__main__":
    main()
