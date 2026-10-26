#!/bin/zsh
set -eu
cd "${0:A:h}/.."
mkdir -p .build/icon .build/FocusIcon.iconset
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" swiftc -parse-as-library scripts/generate-icon.swift -o .build/icon/generate
.build/icon/generate .build/icon
for size in 16 32 128 256 512; do
  cp ".build/icon/dog-$size.png" ".build/FocusIcon.iconset/icon_${size}x${size}.png"
  double=$((size * 2))
  cp ".build/icon/dog-$double.png" ".build/FocusIcon.iconset/icon_${size}x${size}@2x.png"
done
python3 - <<'ICON'
from pathlib import Path
import struct
root = Path('.build/icon')
chunks = []
for tag, size in [('icp4',16),('icp5',32),('icp6',64),('ic07',128),('ic08',256),('ic09',512),('ic10',1024),('ic11',32),('ic12',64),('ic13',256),('ic14',512)]:
    png = (root / f'dog-{size}.png').read_bytes()
    chunks.append(tag.encode('ascii') + struct.pack('>I',len(png)+8) + png)
body = b''.join(chunks)
Path('Sources/FocusCompanion/Resources/FocusIcon.icns').write_bytes(b'icns' + struct.pack('>I',len(body)+8) + body)
ICON
cp .build/icon/dog-1024.png Sources/FocusCompanion/Resources/FocusIcon.png
