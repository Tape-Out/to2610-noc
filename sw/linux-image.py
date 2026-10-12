"""出这一颗的 Linux 载荷：to2610-kvc 的那一份 fw_payload.bin（OpenSBI、内核、根文件系统），只把设备树里的内存
改成 KianV 结点私有段的大小。两颗 KianV 共用这一份，各搬进各自的那一段。

设备树嵌在载荷里（OpenSBI 带着）：按魔数找到它，用 fdtput 改 /memory@80000000 的 reg，原位写回去，
占的还是原来那一块。要装 device-tree-compiler。

用法：linux-image.py <to2610-kvc 的 fw_payload.bin> <输出>
"""
import pathlib
import struct
import subprocess
import sys
import tempfile

RAM, SIZE = 0x80000000, 24 << 20
MAGIC = bytes.fromhex("d00dfeed")

img = bytearray(pathlib.Path(sys.argv[1]).read_bytes())
done, at = 0, img.find(MAGIC)
while at >= 0:
    total, = struct.unpack_from(">I", img, at + 4)
    version, = struct.unpack_from(">I", img, at + 20)
    if version == 17 and 64 <= total <= 1 << 20 and at + total <= len(img):
        with tempfile.TemporaryDirectory() as d:
            f = pathlib.Path(d) / "dtb"
            f.write_bytes(img[at:at + total])
            got = subprocess.run(["fdtget", "-t", "x", f, "/memory@80000000", "reg"], capture_output=True, text=True)
            if got.returncode == 0:
                subprocess.run(["fdtput", "-t", "x", f, "/memory@80000000", "reg", f"{RAM:#x}", f"{SIZE:#x}"], check=True)
                # fdtput 把编的时候留的余量收掉了：总长照原样写回头里，后面补零，占的还是原来那一块
                new = bytearray(f.read_bytes())
                if len(new) > total:
                    sys.exit(f"设备树改完放不回原处：{total} → {len(new)}")
                struct.pack_into(">I", new, 4, total)
                img[at:at + total] = new + bytes(total - len(new))
                done += 1
                print(f"设备树在 {at:#x}，{total} 字节：内存 {got.stdout.strip()} → {RAM:x} {SIZE:x}")
    at = img.find(MAGIC, at + 4)
if not done:
    sys.exit("载荷里没找到带 /memory@80000000 的设备树")
pathlib.Path(sys.argv[2]).write_bytes(img)
