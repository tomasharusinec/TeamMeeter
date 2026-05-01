from PIL import Image, ImageDraw, ImageFilter, ImageFont


def lerp(a: int, b: int, t: float) -> int:
    return int(a + (b - a) * t)


def main():
    size = 1024
    image = Image.new("RGBA", (size, size), (0, 0, 0, 255))
    pixels = image.load()

    top = (139, 26, 44)
    bottom = (26, 10, 10)

    for y in range(size):
        t = y / (size - 1)
        r = lerp(top[0], bottom[0], t)
        g = lerp(top[1], bottom[1], t)
        b = lerp(top[2], bottom[2], t)
        for x in range(size):
            pixels[x, y] = (r, g, b, 255)

    draw = ImageDraw.Draw(image)
    cx, cy = size // 2, size // 2

    # Soft center glow to match app's warm highlights.
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.ellipse((160, 140, 864, 844), fill=(229, 115, 115, 62))
    glow = glow.filter(ImageFilter.GaussianBlur(42))
    image = Image.alpha_composite(image, glow)

    draw = ImageDraw.Draw(image)

    # TM monogram (larger, without center panel)
    try:
        font = ImageFont.truetype("arialbd.ttf", 452)
    except Exception:
        try:
            font = ImageFont.truetype("DejaVuSans-Bold.ttf", 452)
        except Exception:
            font = ImageFont.load_default()

    text = "TM"
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    tx = cx - (tw // 2)
    ty = cy - (th // 2) - 30

    # soft glow behind letters
    glow_text = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    glow_text_draw = ImageDraw.Draw(glow_text)
    glow_text_draw.text((tx, ty), text, font=font, fill=(255, 255, 255, 130))
    glow_text = glow_text.filter(ImageFilter.GaussianBlur(14))
    image = Image.alpha_composite(image, glow_text)
    draw = ImageDraw.Draw(image)

    # subtle depth + white foreground text
    draw.text((tx + 6, ty + 7), text, font=font, fill=(35, 8, 8, 120))
    draw.text((tx, ty), text, font=font, fill=(250, 248, 248, 255))

    # Rounded mask for a modern app icon silhouette.
    mask = Image.new("L", (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle((24, 24, size - 24, size - 24), radius=220, fill=255)
    final_icon = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    final_icon.paste(image, (0, 0), mask)

    final_icon.save("assets/app_icon.png", "PNG")
    print("Generated assets/app_icon.png")


if __name__ == "__main__":
    main()
