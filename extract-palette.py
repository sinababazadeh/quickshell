#!/usr/bin/env python3
import sys
import os
import subprocess
import re
import colorsys
import json

def hex_c(r, g, b):
    return f"#{int(max(0, min(255, r))):02X}{int(max(0, min(255, g))):02X}{int(max(0, min(255, b))):02X}"

def hsv_to_hex(h, s, v):
    r, g, b = colorsys.hsv_to_rgb(h % 1.0, max(0.0, min(1.0, s)), max(0.0, min(1.0, v)))
    return hex_c(r * 255, g * 255, b * 255)

def extract_palette(image_path, mode='balanced'):
    if not image_path or not os.path.isfile(image_path):
        return {}

    try:
        # Quantize down to 16 dominant color clusters directly from the image file on disk
        cmd = ['convert', image_path, '-resize', '64x64', '-colors', '16', '-format', '%c\n', 'histogram:info:']
        out = subprocess.check_output(cmd, text=True, timeout=5)
    except Exception:
        return {}

    colors = []
    for line in out.strip().split('\n'):
        m = re.search(r'(\d+):\s*\(\s*([\d\.]+),\s*([\d\.]+),\s*([\d\.]+)\)', line)
        if m:
            cnt = int(m.group(1))
            r, g, b = float(m.group(2)), float(m.group(3)), float(m.group(4))
            h, s, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
            colors.append({'count': cnt, 'r': int(r), 'g': int(g), 'b': int(b), 'h': h, 's': s, 'v': v})

    if not colors:
        return {}

    by_val = sorted(colors, key=lambda c: c['v'])
    by_count = sorted(colors, key=lambda c: c['count'], reverse=True)
    by_sat = sorted(colors, key=lambda c: c['s'], reverse=True)

    darkest = by_val[0]
    brightest = by_val[-1]

    # Non-dark prominent colors (foreground, subjects, skin tones, etc.)
    non_dark = [c for c in by_count if c['v'] >= 0.25]
    if not non_dark:
        non_dark = by_count

    vibrant_candidate = by_sat[0] if by_sat[0]['s'] > 0.20 else non_dark[0]
    accent = non_dark[0]

    # Base card color (violet): deep, low-luminance version of darkest tone
    base_v = min(0.12, max(0.06, darkest['v']))
    violet = hsv_to_hex(darkest['h'], min(0.5, darkest['s']), base_v)

    # Primary pill body: slightly elevated surface above card background
    primary = hsv_to_hex(darkest['h'], min(0.4, darkest['s']), base_v + 0.10)

    # Empty workspace pip
    bg_pip = hsv_to_hex(darkest['h'], min(0.3, darkest['s']), base_v + 0.05)

    if mode == 'vibrant':
        plum = hex_c(vibrant_candidate['r'], vibrant_candidate['g'], vibrant_candidate['b'])
        attention = hsv_to_hex(vibrant_candidate['h'], min(1.0, vibrant_candidate['s'] + 0.15), max(0.85, vibrant_candidate['v']))
    elif mode == 'deep':
        plum = hsv_to_hex(accent['h'], accent['s'] * 0.8, min(0.65, accent['v']))
        attention = hex_c(accent['r'], accent['g'], accent['b'])
    else:  # balanced
        plum = hex_c(accent['r'], accent['g'], accent['b'])
        attention = hex_c(brightest['r'], brightest['g'], brightest['b']) if brightest['v'] > 0.6 else hsv_to_hex(accent['h'], max(0.2, accent['s'] * 0.7), 0.95)

    # Occupied workspace pip (intermediate between primary and accent)
    indigo = hsv_to_hex(accent['h'], min(0.5, accent['s']), 0.45)

    # Lavender (muted text)
    lavender = hsv_to_hex(accent['h'], min(0.25, accent['s'] * 0.5), 0.82)

    # Ink (main text): crisp contrast
    ink = '#FFFFFF'

    return {
        'plum': plum,
        'primary': primary,
        'violet': violet,
        'attention': attention,
        'indigo': indigo,
        'bg': bg_pip,
        'ink': ink,
        'lavender': lavender
    }

if __name__ == '__main__':
    img_path = sys.argv[1] if len(sys.argv) > 1 else ''
    mode_arg = sys.argv[2] if len(sys.argv) > 2 else 'balanced'
    palette = extract_palette(img_path, mode_arg)
    print(json.dumps(palette))
