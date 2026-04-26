from PIL import Image
import os

# Target iOS dimensions (iPhone 6.5")
TARGET_W = 1284
TARGET_H = 2778

input_dir = r"C:\Users\1\Desktop\high-tech\find_car"
output_dir = r"C:\Users\1\Desktop\high-tech\find_car\ios_screenshots"
os.makedirs(output_dir, exist_ok=True)

for i in range(1, 5):
    path = os.path.join(input_dir, f"{i}.png")
    img = Image.open(path).convert("RGB")
    w, h = img.size
    print(f"{i}.png: {w}x{h}")

    # Crop top to remove Android notch/status bar (about 100px)
    # Crop bottom to remove Android nav bar (about 80px)
    # Crop sides to remove black rounded corner areas
    crop_top = 160
    crop_bottom = 80
    crop_sides = 10

    img = img.crop((crop_sides, crop_top, w - crop_sides, h - crop_bottom))

    # Resize to iOS dimensions
    img = img.resize((TARGET_W, TARGET_H), Image.LANCZOS)

    out_path = os.path.join(output_dir, f"ios_{i}.png")
    img.save(out_path, "PNG")
    print(f"Saved: {out_path}")

print("Done!")
