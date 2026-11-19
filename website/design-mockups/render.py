"""Render the mockup pages to PNG slices with headless Chrome."""
import os, re, subprocess, sys
from PIL import Image

CH = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
HERE = os.path.dirname(os.path.abspath(__file__))
BASE = "file:///" + HERE.replace("\\", "/") + "/"
FLAGS = ["--headless=new", "--disable-gpu", "--hide-scrollbars", "--virtual-time-budget=12000"]

def title(url, w):
    out = subprocess.run([CH, *FLAGS, f"--window-size={w},900", "--dump-dom", url], capture_output=True, text=True, encoding="utf-8", errors="ignore").stdout
    return re.search(r"<title>([^<]*)", out).group(1)

def shot(url, w, h, scale, path):
    subprocess.run([CH, *FLAGS, f"--window-size={w},{h}", f"--force-device-scale-factor={scale}", f"--screenshot={path}", url], capture_output=True)

def render(page, mode):
    if mode == "desktop":
        url, w, scale, crop_w = BASE + page + ".html", 1440, 1, 1440
    else:
        url, w, scale, crop_w = BASE + "mobile.html?" + page + ".html", 504, 2, 390
    t = title(url, w)
    parts = t.split("|")
    h = int(parts[1][1:])
    cuts = [(c.split(":")[0], int(c.split(":")[1])) for c in parts[2].split(",")]
    tmp = os.path.join(HERE, "_tmp.png")
    shot(url, w, h, scale, tmp)
    im = Image.open(tmp).convert("RGB")
    im = im.crop((0, 0, crop_w * scale, min(im.size[1], h * scale)))
    out = os.path.join(HERE, mode, page)
    os.makedirs(out, exist_ok=True)
    for f in os.listdir(out):
        os.remove(os.path.join(out, f))
    for i, (name, top) in enumerate(cuts):
        bottom = cuts[i + 1][1] if i + 1 < len(cuts) else h
        im.crop((0, top * scale, im.size[0], bottom * scale)).save(os.path.join(out, name + ".png"))
    im.save(os.path.join(HERE, mode, page + "-full.png"))
    os.remove(tmp)
    print(page, mode, im.size, [c[0] for c in cuts])

for page in (sys.argv[1:] or ["home", "partner"]):
    for mode in ("desktop", "mobile"):
        render(page, mode)
