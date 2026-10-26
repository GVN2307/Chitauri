import os
import math
from PIL import Image, ImageDraw, ImageFont, ImageFilter

def create_chitauri_icon(size):
    # Render at 4x resolution for super-sampled anti-aliasing
    scale = 4
    canvas_size = size * scale
    img = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    center = canvas_size / 2.0
    radius = canvas_size * 0.46

    # Draw rounded dark background with subtle border
    bg_color = (13, 17, 23, 255)       # Dark sleek slate/obsidian
    border_color = (0, 230, 118, 180)   # Neon green glow border
    
    # Outer subtle glow
    for i in range(scale * 3, 0, -1):
        alpha = int(30 * (1 - i / (scale * 3)))
        glow_r = radius + i * 2
        draw.ellipse(
            [center - glow_r, center - glow_r, center + glow_r, center + glow_r],
            fill=(0, 255, 136, alpha)
        )

    # Main circular app badge
    draw.ellipse(
        [center - radius, center - radius, center + radius, center + radius],
        fill=bg_color,
        outline=border_color,
        width=int(scale * 3)
    )

    # Subtle soundwave/concentric arcs inside the badge
    arc_color = (20, 45, 35, 180)
    for r_offset in [0.36, 0.28, 0.20]:
        inner_r = canvas_size * r_offset
        draw.arc(
            [center - inner_r, center - inner_r, center + inner_r, center + inner_r],
            start=45, end=315,
            fill=arc_color,
            width=int(scale * 1.5)
        )

    # Draw stylized geometric glowing Green "C"
    # Outer arc of the "C"
    c_outer_r = canvas_size * 0.32
    c_inner_r = canvas_size * 0.18
    stroke_w = int(c_outer_r - c_inner_r)
    c_mid_r = (c_outer_r + c_inner_r) / 2.0

    # Draw C using pie slices and arcs
    green_start = (0, 255, 136, 255)    # Vibrant electric neon green
    green_end = (0, 200, 83, 255)      # Deep emerald green

    # Draw thick arc for the C body from 45 deg to 315 deg (open on the right side)
    draw.arc(
        [center - c_mid_r, center - c_mid_r, center + c_mid_r, center + c_mid_r],
        start=45, end=315,
        fill=green_start,
        width=stroke_w
    )

    # Cap the top and bottom ends of the C with rounded terminals
    angle_top = math.radians(45)
    top_x = center + c_mid_r * math.cos(angle_top)
    top_y = center + c_mid_r * math.sin(angle_top)
    cap_r = stroke_w / 2.0

    draw.ellipse(
        [top_x - cap_r, top_y - cap_r, top_x + cap_r, top_y + cap_r],
        fill=green_start
    )

    angle_bottom = math.radians(315)
    bot_x = center + c_mid_r * math.cos(angle_bottom)
    bot_y = center + c_mid_r * math.sin(angle_bottom)

    draw.ellipse(
        [bot_x - cap_r, bot_y - cap_r, bot_x + cap_r, bot_y + cap_r],
        fill=green_end
    )

    # Draw a futuristic audio pulse dot inside the opening of the C
    pulse_x = center + canvas_size * 0.25
    pulse_y = center
    pulse_r = canvas_size * 0.05
    draw.ellipse(
        [pulse_x - pulse_r, pulse_y - pulse_r, pulse_x + pulse_r, pulse_y + pulse_r],
        fill=(0, 255, 170, 240)
    )

    # Scale down with high quality Lanczos filter for crisp anti-aliasing
    return img.resize((size, size), Image.Resampling.LANCZOS)

def main():
    sizes = {
        "res/mipmap-mdpi": 48,
        "res/mipmap-hdpi": 72,
        "res/mipmap-xhdpi": 96,
        "res/mipmap-xxhdpi": 144,
        "res/mipmap-xxxhdpi": 192,
    }

    for folder, size in sizes.items():
        os.makedirs(folder, exist_ok=True)
        icon = create_chitauri_icon(size)
        path = os.path.join(folder, "ic_launcher.png")
        icon.save(path, "PNG")
        print(f"Generated {path} ({size}x{size})")

    # High-resolution logos
    os.makedirs("assets", exist_ok=True)
    os.makedirs("dist", exist_ok=True)
    hi_res = create_chitauri_icon(512)
    hi_res.save("assets/logo.png", "PNG")
    hi_res.save("dist/logo.png", "PNG")
    print("Generated assets/logo.png and dist/logo.png (512x512)")

if __name__ == "__main__":
    main()
