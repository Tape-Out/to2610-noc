"""拼 Flash 镜像：引导程序在 1 MiB，载荷带 16 字节的头放在它后面 64 KiB 处。四个核用同一份载荷，各自搬进自己那段 SDRAM。

布局与 to2610-kvc 的相同，头是魔数、字节数、按 32 位小端字求的和、保留。

用法：pack.py <boot.bin> <载荷> <输出>
"""
import pathlib
import struct
import sys

BOOT, PAYLOAD, MAGIC = 0x100000, 0x110000, 0x4C50564B
# 每个核私有的那段 SDRAM 有 6 MiB，顶上 8 KiB 归引导程序
ROOM = (6 << 20) - 0x2000

boot = pathlib.Path(sys.argv[1]).read_bytes()
load = pathlib.Path(sys.argv[2]).read_bytes()
if len(boot) > PAYLOAD - BOOT:
    sys.exit(f"引导程序 {len(boot)} 字节，放不进 64 KiB")
if len(load) > ROOM:
    sys.exit(f"载荷 {len(load)} 字节，放不进私有的那段 SDRAM")
body = load + b"\0" * (-len(load) % 4)
total = sum(struct.unpack(f"<{len(body) // 4}I", body)) & 0xFFFFFFFF
img = bytearray(b"\xff" * (PAYLOAD + 16 + len(body)))
img[BOOT:BOOT + len(boot)] = boot
img[PAYLOAD:PAYLOAD + 16] = struct.pack("<4I", MAGIC, len(load), total, 0)
img[PAYLOAD + 16:] = body
pathlib.Path(sys.argv[3]).write_bytes(img)
print(f"{sys.argv[3]}：引导程序 {len(boot)} 字节，载荷 {len(load)} 字节，共 {len(img)} 字节")
