#!/bin/bash
# usage: shot.sh name  -> scratch/emu/name.png (scaled to 1/3)
cd "C:/Users/Admin/Desktop/All websites/InnovateHive/BookALook/scratch/emu"
adb -s emulator-5554 exec-out screencap -p > "$1_full.png"
python -I -c "from PIL import Image; import sys; im=Image.open(sys.argv[1]); im.resize((im.width//3, im.height//3)).save(sys.argv[2])" "$1_full.png" "$1.png"
echo "C:/Users/Admin/Desktop/All websites/InnovateHive/BookALook/scratch/emu/$1.png"
