"""FloatSwitch アプリアイコン生成スクリプト

ウィンドウ重なり + 切り替え矢印のデザイン
- 背景: パープル〜ブルーのグラデーション
- 2枚の白ウィンドウが斜めに重なる
- 中央に双方向矢印
"""

from PIL import Image, ImageDraw, ImageFont
import math
import os

SIZE = 1024
ICON_SIZES = [16, 32, 64, 128, 256, 512, 1024]


def lerp_color(c1: tuple, c2: tuple, t: float) -> tuple:
    return tuple(int(a + (b - a) * t) for a, b in zip(c1, c2))


def draw_gradient(img: Image.Image, c1: tuple, c2: tuple):
    """斜めグラデーション"""
    draw = ImageDraw.Draw(img)
    w, h = img.size
    for y in range(h):
        for x in range(w):
            t = (x / w * 0.6 + y / h * 0.4)
            t = max(0, min(1, t))
            color = lerp_color(c1, c2, t)
            draw.point((x, y), fill=color)


def draw_rounded_rect(draw: ImageDraw.Draw, bbox: tuple, radius: int,
                      fill=None, outline=None, width=0):
    x0, y0, x1, y1 = bbox
    draw.rounded_rectangle(bbox, radius=radius, fill=fill, outline=outline, width=width)


def draw_window(img: Image.Image, x: int, y: int, w: int, h: int,
                radius: int, shadow_offset: int = 12, opacity: int = 230):
    """影付きウィンドウを描画"""
    # 影レイヤー
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    shadow_bbox = (x + shadow_offset, y + shadow_offset,
                   x + w + shadow_offset, y + h + shadow_offset)
    sd.rounded_rectangle(shadow_bbox, radius=radius, fill=(0, 0, 0, 60))
    # ぼかし代わりに複数の半透明矩形
    for i in range(1, 4):
        sd.rounded_rectangle(
            (shadow_bbox[0] - i * 2, shadow_bbox[1] - i * 2,
             shadow_bbox[2] + i * 2, shadow_bbox[3] + i * 2),
            radius=radius + i * 2,
            fill=(0, 0, 0, max(5, 20 - i * 6))
        )
    img.alpha_composite(shadow)

    # ウィンドウ本体
    win = Image.new("RGBA", img.size, (0, 0, 0, 0))
    wd = ImageDraw.Draw(win)
    win_bbox = (x, y, x + w, y + h)
    wd.rounded_rectangle(win_bbox, radius=radius, fill=(255, 255, 255, opacity))

    # タイトルバー領域
    title_h = int(h * 0.14)
    # タイトルバーの区切り線
    wd.line([(x + radius // 2, y + title_h), (x + w - radius // 2, y + title_h)],
            fill=(200, 200, 210, 120), width=2)

    # 信号ボタン（赤・黄・緑）
    dot_r = int(h * 0.028)
    dot_y = y + title_h // 2
    dot_start_x = x + int(w * 0.08)
    dot_gap = int(dot_r * 3.2)
    colors = [(255, 95, 87), (255, 189, 46), (39, 201, 63)]
    for i, color in enumerate(colors):
        cx = dot_start_x + i * dot_gap
        wd.ellipse((cx - dot_r, dot_y - dot_r, cx + dot_r, dot_y + dot_r),
                   fill=(*color, 220))

    # コンテンツ領域のダミー行
    line_y = y + title_h + int(h * 0.10)
    line_h = int(h * 0.04)
    line_gap = int(h * 0.07)
    for i in range(4):
        lw = int(w * (0.7 - i * 0.1))
        ly = line_y + i * line_gap
        if ly + line_h > y + h - radius:
            break
        wd.rounded_rectangle(
            (x + int(w * 0.08), ly, x + int(w * 0.08) + lw, ly + line_h),
            radius=line_h // 2,
            fill=(180, 185, 200, 80)
        )

    img.alpha_composite(win)


def draw_switch_arrow(img: Image.Image, cx: int, cy: int, size: int):
    """双方向矢印（⇄）を描画"""
    arrow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ad = ImageDraw.Draw(arrow)

    # 円形背景
    bg_r = size
    ad.ellipse(
        (cx - bg_r, cy - bg_r, cx + bg_r, cy + bg_r),
        fill=(80, 60, 140, 200)
    )

    # 矢印
    lw = max(4, size // 8)
    arrow_len = int(size * 1.1)
    head = int(size * 0.35)

    # 右向き矢印（上段）
    ay1 = cy - size // 4
    ad.line([(cx - arrow_len // 2, ay1), (cx + arrow_len // 2, ay1)],
            fill=(255, 255, 255, 240), width=lw)
    # 矢じり
    ad.polygon([
        (cx + arrow_len // 2 + 2, ay1),
        (cx + arrow_len // 2 - head, ay1 - head),
        (cx + arrow_len // 2 - head, ay1 + head),
    ], fill=(255, 255, 255, 240))

    # 左向き矢印（下段）
    ay2 = cy + size // 4
    ad.line([(cx + arrow_len // 2, ay2), (cx - arrow_len // 2, ay2)],
            fill=(255, 255, 255, 240), width=lw)
    ad.polygon([
        (cx - arrow_len // 2 - 2, ay2),
        (cx - arrow_len // 2 + head, ay2 - head),
        (cx - arrow_len // 2 + head, ay2 + head),
    ], fill=(255, 255, 255, 240))

    img.alpha_composite(arrow)


def generate_icon():
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

    # macOS アイコン形状: 角丸正方形
    margin = int(SIZE * 0.08)
    corner_r = int(SIZE * 0.22)

    # グラデーション背景を角丸にクリップ
    bg = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw_gradient(bg, (100, 70, 180), (50, 120, 200))

    mask = Image.new("L", (SIZE, SIZE), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle(
        (margin, margin, SIZE - margin, SIZE - margin),
        radius=corner_r, fill=255
    )
    bg.putalpha(mask)
    img.alpha_composite(bg)

    # 内側のサイズ
    inner = SIZE - margin * 2

    # 背面ウィンドウ（左上にずれて配置）
    win_w = int(inner * 0.58)
    win_h = int(inner * 0.48)
    draw_window(img,
                x=margin + int(inner * 0.08),
                y=margin + int(inner * 0.12),
                w=win_w, h=win_h,
                radius=int(win_w * 0.06),
                shadow_offset=10,
                opacity=180)

    # 前面ウィンドウ（右下にずれて配置）
    draw_window(img,
                x=margin + int(inner * 0.34),
                y=margin + int(inner * 0.38),
                w=win_w, h=win_h,
                radius=int(win_w * 0.06),
                shadow_offset=14,
                opacity=240)

    # 切り替え矢印（2つのウィンドウの間）
    arrow_cx = margin + int(inner * 0.50)
    arrow_cy = margin + int(inner * 0.48)
    draw_switch_arrow(img, arrow_cx, arrow_cy, int(inner * 0.10))

    return img


def main():
    icon = generate_icon()

    # 出力先
    out_dir = os.path.join(
        os.path.dirname(os.path.dirname(__file__)),
        "FloatSwitch", "FloatSwitch", "Assets.xcassets", "AppIcon.appiconset"
    )
    os.makedirs(out_dir, exist_ok=True)

    images_json = []

    for size in ICON_SIZES:
        for scale in [1, 2]:
            pixel_size = size * scale
            if pixel_size > 1024:
                continue

            resized = icon.resize((pixel_size, pixel_size), Image.LANCZOS)
            filename = f"icon_{size}x{size}@{scale}x.png"
            resized.save(os.path.join(out_dir, filename), "PNG")
            print(f"  Generated {filename} ({pixel_size}x{pixel_size})")

            images_json.append({
                "filename": filename,
                "idiom": "mac",
                "scale": f"{scale}x",
                "size": f"{size}x{size}"
            })

    # Contents.json
    import json
    contents = {
        "images": images_json,
        "info": {"author": "xcode", "version": 1}
    }
    with open(os.path.join(out_dir, "Contents.json"), "w") as f:
        json.dump(contents, f, indent=2)

    print(f"\n  All icons saved to {out_dir}")


if __name__ == "__main__":
    main()
