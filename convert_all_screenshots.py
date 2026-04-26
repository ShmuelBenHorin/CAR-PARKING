from PIL import Image
import os

base = r"C:\Users\1\Desktop\high-tech\find_car\screen_shots"
output_base = r"C:\Users\1\Desktop\high-tech\find_car\ios_screenshots_all"

# iOS target dimensions
IPHONE = (1284, 2778)       # iPhone 6.5"
IPAD_PORTRAIT = (2048, 2732)  # iPad Pro 12.9" portrait
IPAD_LANDSCAPE = (2732, 2048) # iPad Pro 12.9" landscape

configs = {
    "mobile": {
        "target": IPHONE,
        "crop_top": 160,
        "crop_bottom": 80,
        "crop_sides": 10,
    },
    "tab-7": {
        "target": IPAD_PORTRAIT,
        "crop_top": 50,
        "crop_bottom": 50,
        "crop_sides": 0,
    },
    "tab-10": {
        "target": IPAD_LANDSCAPE,
        "crop_top": 45,
        "crop_bottom": 45,
        "crop_sides": 0,
    },
}

for lang in ["en", "he"]:
    for folder, cfg in configs.items():
        input_dir = os.path.join(base, lang, folder)
        if not os.path.exists(input_dir):
            continue

        output_dir = os.path.join(output_base, lang, folder)
        os.makedirs(output_dir, exist_ok=True)

        files = sorted([f for f in os.listdir(input_dir) if f.endswith(".png")])
        for idx, fname in enumerate(files, 1):
            path = os.path.join(input_dir, fname)
            img = Image.open(path).convert("RGB")
            w, h = img.size

            ct = cfg["crop_top"]
            cb = cfg["crop_bottom"]
            cs = cfg["crop_sides"]

            img = img.crop((cs, ct, w - cs if cs > 0 else w, h - cb))
            img = img.resize(cfg["target"], Image.LANCZOS)

            out_path = os.path.join(output_dir, f"{idx}.png")
            img.save(out_path, "PNG")
            print(f"Saved: {lang}/{folder}/{idx}.png ({cfg['target'][0]}x{cfg['target'][1]})")

print("\nDone!")
