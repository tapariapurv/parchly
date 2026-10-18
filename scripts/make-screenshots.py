#!/usr/bin/env python3
"""Builds 2880x1800 Mac App Store screenshots from docs/assets/*.jpg. Run: python3 scripts/make-screenshots.py"""
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 2880, 1800
PAPER, INK, MUTED = (245, 243, 239), (28, 26, 23), (111, 106, 99)
SERIF = "/System/Library/Fonts/NewYork.ttf"
SHOTS = [
    ("document", "Markdown that reads like a page", "Syntax fades away. Your file stays plain text."),
    ("source", "Raw Markdown, one keystroke away", "Source mode with line numbers: ⌃⌘2."),
    ("split", "A live, GitHub-style preview", "Tables, task lists and footnotes, side by side."),
    ("sidebar", "Every .md in the folder, ⌘P away", "Fuzzy-find files and jump through headings."),
    ("quicklook", "Press Space in Finder to preview", "The built-in Quick Look extension renders any .md."),
    ("dark", "Calm in Dark Mode too", "Light, Dark or follow the system."),
]

def font(size, weight):
    f = ImageFont.truetype(SERIF, size)
    try: f.set_variation_by_axes([min(256, max(12, size // 2)), weight, 0])  # opsz, wght, grade
    except Exception: pass
    return f

for i, (name, title, sub) in enumerate(SHOTS, 1):
    bg = Image.new("RGB", (W, H), PAPER)
    d = ImageDraw.Draw(bg)
    for text, f, y, color in [(title, font(112, 700), 150, INK), (sub, font(54, 400), 300, MUTED)]:
        w = d.textlength(text, font=f)
        d.text(((W - w) / 2, y), text, font=f, fill=color)
    shot = Image.open(f"docs/assets/{name}.jpg").convert("RGB")
    shot.thumbnail((2300, 1330))
    x, y = (W - shot.width) // 2, 420
    shadow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(shadow).rounded_rectangle((x, y + 30, x + shot.width, y + shot.height + 30), 40, fill=110)
    bg.paste((60, 45, 25), mask=shadow.filter(ImageFilter.GaussianBlur(60)))
    mask = Image.new("L", shot.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, shot.width - 1, shot.height - 1), 26, fill=255)
    bg.paste(shot, (x, y), mask)
    bg.save(f"appstore/screenshots/en-US/{i}_{name}.png", optimize=True)
    print("wrote", name)
