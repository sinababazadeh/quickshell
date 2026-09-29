#!/usr/bin/env bash
# =============================================================================
#  SANITIZE-WALLPAPERS.SH — Auto-detects and converts unsupported images for Qt
# =============================================================================
#  Qt Quick's Image element requires standard sRGB JPEG/PNG files. When images
#  are downloaded from modern browsers, they are often WebP, AVIF, HEIC, or
#  renamed with .jpg/.jpeg extensions while retaining WebP/AVIF headers.
#  This script inspects files in ~/.config/quickshell/wallpapers and auto-converts
#  them to clean, 100% Qt-compatible baseline JPEG images.
# =============================================================================

set -e

TARGET="${1:-$HOME/.config/quickshell/wallpapers}"

sanitize_file() {
    local file="$1"
    [ -f "$file" ] || return 0
    [ -s "$file" ] || return 0

    local base
    base=$(basename "$file")
    # Skip state files or dotfiles
    [[ "$base" == .* ]] && return 0

    local mime ext
    mime=$(file -b --mime-type "$file" 2>/dev/null || true)
    ext="${file##*.}"
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')

    local needs_convert=0

    case "$mime" in
        image/webp|image/avif|image/heic|image/heif|image/tiff|image/bmp|image/x-ms-bmp)
            needs_convert=1
            ;;
        image/jpeg)
            # Check for CMYK color profile which Qt cannot decode
            if file "$file" 2>/dev/null | grep -iq "cmyk"; then
                needs_convert=1
            fi
            ;;
        image/png)
            # Standard PNG is usually fine, but check for corruption
            ;;
        *)
            # If named as an image extension but MIME doesn't match standard
            if [[ "$ext" =~ ^(jpg|jpeg|png|webp|avif|bmp)$ ]]; then
                needs_convert=1
            fi
            ;;
    esac

    # Also detect when extension is .jpg/.jpeg but file header is not JPEG
    if [[ "$ext" =~ ^(jpg|jpeg)$ ]] && [ "$mime" != "image/jpeg" ]; then
        needs_convert=1
    fi

    if [ "$needs_convert" -eq 1 ]; then
        local tmp="${file}.sanitized.jpg"
        local converted=0

        if command -v magick >/dev/null 2>&1; then
            magick "$file" -auto-orient -colorspace sRGB -quality 95 "$tmp" 2>/dev/null && converted=1
        elif command -v convert >/dev/null 2>&1; then
            convert "$file" -auto-orient -colorspace sRGB -quality 95 "$tmp" 2>/dev/null && converted=1
        elif command -v ffmpeg >/dev/null 2>&1; then
            ffmpeg -y -v error -i "$file" -pix_fmt yuvj420p -q:v 2 "$tmp" 2>/dev/null && converted=1
        fi

        if [ "$converted" -eq 1 ] && [ -s "$tmp" ]; then
            # If the original had a non-jpg extension like .webp or .avif, keep both or make .jpg
            if [[ "$ext" == "webp" || "$ext" == "avif" || "$ext" == "heic" ]]; then
                local new_name="${file%.*}.jpg"
                mv -f "$tmp" "$new_name"
                echo "[quickshell] Converted $base to $new_name"
            else
                mv -f "$tmp" "$file"
                echo "[quickshell] Sanitized $base into valid JPEG"
            fi
        else
            rm -f "$tmp" 2>/dev/null || true
            echo "[quickshell] Could not convert $base (MIME: $mime)" >&2
        fi
    fi
}

if [ -f "$TARGET" ]; then
    sanitize_file "$TARGET"
elif [ -d "$TARGET" ]; then
    for f in "$TARGET"/*; do
        [ -f "$f" ] && sanitize_file "$f"
    done
fi
exit 0
