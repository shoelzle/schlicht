"""Render preview images of the "Schlicht" watch face for the README.

The drawing mirrors watchfaces/schlicht/source/SchlichtView.mc (454 px design
size, time 10:09:36, example data below). Run from the repository root:

    python3 tools/render_previews.py

It writes docs/images/schlicht-plain.svg and, if `rsvg-convert` (librsvg)
is installed, the matching PNG plus the launcher icon. No other dependencies.
"""
import math
import os
import shutil
import subprocess
import sys

C = 227.0  # centre
W = 454

# Time shown in all previews: 10:09:36
H, M, S = 10, 9, 36
hour_deg = (H % 12 + M / 60 + S / 3600) * 30
min_deg = (M + S / 60) * 6
sec_deg = S * 6


def pt(r, deg):
    a = math.radians(deg - 90)
    return C + r * math.cos(a), C + r * math.sin(a)


def ticks():
    """60 grey dots near the edge; the five-minute dots are larger and lighter."""
    out = []
    for i in range(60):
        major = i % 5 == 0
        x, y = pt(219, i * 6)
        r, col = (3, "#a6a6a6") if major else (1.6, "#8a8a8a")
        out.append(f'<circle cx="{x:.2f}" cy="{y:.2f}" r="{r}" fill="{col}"></circle>')
    return out


# Soft edge: two translucent layers (extra width, opacity) under the white core
SOFT_EDGE = [(2.0, "#404040"), (1.0, "#808080")]   # white at 25 % / 50 % over black


def hand(deg, length, tail, width, color="#ffffff", soft=True):
    # rounded bar drawn pointing up, then rotated around the centre
    layers = (SOFT_EDGE if soft else []) + [(0.0, color)]
    out = []
    for extra, fill in layers:
        w = width + extra
        out.append(
            f'<rect x="{C - w / 2:.2f}" y="{C - length - extra / 2:.2f}" width="{w}" '
            f'height="{length + tail + extra}" rx="{w / 2}" fill="{fill}" '
            f'transform="rotate({deg:.2f} {C} {C})"></rect>'
        )
    return "".join(out)


def face(variant):
    parts = ticks()
    parts.append(extras())
    parts.append(hand(hour_deg, 120, 16, 8.28))
    parts.append(hand(min_deg, 198, 16, 5.18))
    x1, y1 = pt(-34, sec_deg)
    x2, y2 = pt(204, sec_deg)
    parts.append(
        f'<line x1="{x1:.2f}" y1="{y1:.2f}" x2="{x2:.2f}" y2="{y2:.2f}" '
        f'stroke="#ffffff" stroke-width="1.84" stroke-linecap="round"></line>'
    )
    parts.append(f'<circle cx="{C}" cy="{C}" r="6" fill="#ffffff"></circle>')
    parts.append(f'<circle cx="{C}" cy="{C}" r="2" fill="#000000"></circle>')
    return "\n".join(parts)


FONT = "Roboto, Inter, Helvetica, Arial, sans-serif"
ICON, TXT, DATE, SUN = "#8a8a8a", "#bdbdbd", "#d6d6d6", "#d4c27e"
HEART = ('<path d="M0 6.5 C -9.5 0.5 -9 -7 -4.2 -7 C -1.8 -7 -0.4 -5.4 0 -4.2 '
         'C 0.4 -5.4 1.8 -7 4.2 -7 C 9 -7 9.5 0.5 0 6.5 Z"></path>')

# Example data shown in the preview
SUNRISE, SUNSET = (7, 28), (16, 52)
HEART_RATE, NOTIFICATIONS, DATE_TEXT = "60", 3, "Sa 7"


def dial(h, m):
    return ((h % 12) + m / 60) * 30


def text(x, y, s, size, fill, anchor="middle"):
    return (f'<text x="{x:.1f}" y="{y + size * 0.36:.1f}" text-anchor="{anchor}" '
            f'font-family="{FONT}" font-size="{size}" fill="{fill}">{s}</text>')


def ppt(r, deg):
    a = math.radians(deg)
    return C + r * math.sin(a), C - r * math.cos(a)


# Example hourly forecast for the day arc and the colours used by WeatherArc.mc
FORECAST = [(10.16, "sun"), (12.0, "sun"), (13.0, "partly"), (14.0, "cloudy"),
            (14.8, "rain"), (15.6, "partly"), (16.3, "evening"), (16 + 52 / 60, "evening")]
WEATHER = {"sun": "#b89a3e", "partly": "#8f8a72", "cloudy": "#5c5c5c",
           "rain": "#4d6478", "evening": "#a85a44"}


def _mix(a, b, t):
    ca = [int(a[i:i + 2], 16) for i in (1, 3, 5)]
    cb = [int(b[i:i + 2], 16) for i in (1, 3, 5)]
    return "#%02x%02x%02x" % tuple(round(x + (y - x) * t) for x, y in zip(ca, cb))


def _color_at(h):
    for (h0, c0), (h1, c1) in zip(FORECAST, FORECAST[1:]):
        if h0 <= h <= h1:
            t = (h - h0) / (h1 - h0)
            return _mix(WEATHER[c0], WEATHER[c1], t * t * (3 - 2 * t))
    return WEATHER[FORECAST[-1][1]]


def weather_arc(r, width=2.5):
    now = (H % 12) + M / 60 + S / 3600
    end = SUNSET[0] - 12 + SUNSET[1] / 60 + 12  # keep 24 h value for colours
    out, step = [], 1 / 60
    # soft start: one hour before the hour hand, fading in from black to the colour of "now"
    h = now - 1
    while h < now - 1e-6:
        h2 = min(h + step, now)
        f = ((h + h2) / 2 - (now - 1))
        f = f * f * (3 - 2 * f)
        x1, y1 = ppt(r, dial(int(h), (h % 1) * 60) - 0.15)
        x2, y2 = ppt(r, dial(int(h2), (h2 % 1) * 60) + 0.15)
        out.append(f'<path d="M {x1:.2f} {y1:.2f} A {r} {r} 0 0 1 {x2:.2f} {y2:.2f}" fill="none" '
                   f'stroke="{_mix("#000000", _color_at(now), f)}" stroke-width="{width}"></path>')
        h = h2
    h = now
    while h < end - 1e-6:
        h2 = min(h + step, end)
        x1, y1 = ppt(r, dial(int(h), (h % 1) * 60) - 0.15)
        x2, y2 = ppt(r, dial(int(h2), (h2 % 1) * 60) + 0.15)
        mid = (h + h2) / 2
        col = _color_at(mid)
        fade_start = end - 0.4          # soft end at the moon: 24 min = two minute dots
        if mid > fade_start:
            f = (mid - fade_start) / 0.4
            col = _mix(col, "#000000", f * f * (3 - 2 * f))
        out.append(f'<path d="M {x1:.2f} {y1:.2f} A {r} {r} 0 0 1 {x2:.2f} {y2:.2f}" fill="none" '
                   f'stroke="{col}" stroke-width="{width}"></path>')
        h = h2
    return "".join(out)


def extras():
    out = []
    # day arc: from "now" (hour hand) to sunset, radius 193, in forecast colours
    r = 193
    out.append(weather_arc(r))
    for (h, m), off in ((SUNRISE, -15), (SUNSET, 15)):
        x, y = ppt(r, dial(h, m))
        if (h, m) == SUNRISE:   # small sun: disc with eight rays
            out.append(f'<circle cx="{x:.2f}" cy="{y:.2f}" r="6" fill="{SUN}"></circle>')
            for i in range(8):
                a = math.radians(i * 45)
                out.append(f'<line x1="{x + 9.5 * math.sin(a):.2f}" y1="{y - 9.5 * math.cos(a):.2f}" '
                           f'x2="{x + 14 * math.sin(a):.2f}" y2="{y - 14 * math.cos(a):.2f}" '
                           f'stroke="{SUN}" stroke-width="2.5"></line>')
        else:                   # small crescent moon: disc with a black disc cut out
            out.append(f'<circle cx="{x:.2f}" cy="{y:.2f}" r="13" fill="{TXT}"></circle>')
            out.append(f'<circle cx="{x + 6.2:.2f}" cy="{y - 4.6:.2f}" r="11" fill="#000000"></circle>')
        lx, ly = ppt(163, dial(h, m) + off)
        out.append(text(lx, ly, f"{h:02d}:{m:02d}", 25, TXT))
    # date and heart rate
    # date and heart: inner edges 82 px from the centre, heart exactly as tall as the digits
    size = 29.9
    out.append(text(C + 82, C, DATE_TEXT, size, DATE, "start"))
    k = size * 0.711 / 28.92
    heart_w = 32 * k
    hx = C - 82 - heart_w / 2
    pts = []
    for i in range(64):
        t = i * 2 * math.pi / 64
        x = 16 * math.sin(t) ** 3
        y = -(13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)) - 2.54
        pts.append(f"{hx + x * k:.2f},{C + y * k:.2f}")
    out.append(f'<polygon points="{" ".join(pts)}" fill="none" stroke="{DATE}" stroke-width="2.64" '
               f'stroke-linejoin="round"></polygon>')
    out.append(text(C - 82 - heart_w - 7, C, HEART_RATE, size, DATE, "end"))
    # notification dots, fading upwards
    for k in range(min(NOTIFICATIONS, 5)):
        v = round(0x8a * (1 - k / 4))
        if v:
            out.append(f'<circle cx="227" cy="{176 - 13 * k}" r="3" fill="#{v:02x}{v:02x}{v:02x}"></circle>')
    return "\n".join(out)


VARIANTS = {
    "plain": "Schlicht watch face at 10:09 with day arc, date, heart rate and three notification dots",
}

SVG = """<svg xmlns="http://www.w3.org/2000/svg" width="454" height="454" viewBox="0 0 454 454" role="img" aria-label="{label}">
<circle cx="227" cy="227" r="227" fill="#000000"></circle>
{body}
</svg>
"""


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    images = os.path.join(root, "docs", "images")
    icon = os.path.join(root, "watchfaces", "schlicht", "resources", "drawables", "launcher_icon.png")
    os.makedirs(images, exist_ok=True)
    rsvg = shutil.which("rsvg-convert")
    for key, label in VARIANTS.items():
        svg = os.path.join(images, f"schlicht-{key}.svg")
        with open(svg, "w") as f:
            f.write(SVG.format(label=label, body=face(key)))
        if rsvg:
            subprocess.run([rsvg, "-w", "454", "-h", "454", svg, "-o", svg[:-4] + ".png"], check=True)
    if rsvg:
        plain = os.path.join(images, "schlicht-plain.svg")
        subprocess.run([rsvg, "-w", "70", "-h", "70", plain, "-o", icon], check=True)
    else:
        print("rsvg-convert not found: only SVGs written", file=sys.stderr)


if __name__ == "__main__":
    main()
