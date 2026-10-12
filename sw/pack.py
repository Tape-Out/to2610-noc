"""拼 Flash 镜像。

  0x100000  引导程序，64 KiB 以内；KianV 与 Hazard3 的结点从这里起步
  0x110000  目录：魔数 "NOCD"、0 号结点起来后先放开哪几个结点（写进 RUN 的值）、四个结点各自那份载荷在 Flash 里的偏移（0 是没有）
  0x180000  PicoRV32 的程序，就地执行（它的复位向量），512 KiB 以内
  0x200000  起，各份载荷

一份载荷：头四个字（魔数 "NOCP"、段数、各段数据按 32 位小端字求的和、入口地址），每段两个字（目的地址、字数），然后是各段的数据。
字数最高位是 1 的段没有数据，引导程序把那一段清零：载荷里 64 KiB 以上的整块零不进 Flash（OpenSBI 到内核之间就空着 4 MiB）。
几个结点可以共用一份载荷，各自搬进自己那段 SDRAM 的 0x8000_0000 处。

用法：pack.py <boot.bin> <输出> [--pico <程序>] [--run <掩码>] <结点号…>=<载荷>…
  例：pack.py boot.bin linux.flash --pico pico.bin --run 0xf 01=fw_payload.bin 2=rtos.bin
"""
import argparse
import pathlib
import struct
import sys

BOOT, DIR, PICO, DATA, END = 0x100000, 0x110000, 0x180000, 0x200000, 16 << 20
RAM = 0x80000000
DIR_MAGIC, LOAD_MAGIC, ZERO = 0x44434F4E, 0x50434F4E, 0x80000000
# 各结点私有段的大小，与 patch/mkpatch.py 里给仲裁的是同一组数；段顶 8 KiB 归引导程序
PRIV = [24 << 20, 24 << 20, 4 << 20, 4 << 20]
KEEP = 0x2000
BLOCK, GAP = 4096, 16


def segments(load: bytes) -> list[tuple[int, bytes | None, int]]:
    """把载荷切成段：(偏移, 数据, 字节数)；数据是 None 的那一段全是零。"""
    blocks = [load[i:i + BLOCK] for i in range(0, len(load), BLOCK)]
    zero = [not any(b) for b in blocks]
    out, i = [], 0
    while i < len(blocks):
        j = i
        while j < len(blocks) and zero[j] == zero[i]:
            j += 1
        # 短的零块并进前后的数据里，不单列
        if zero[i] and (j - i < GAP or i == 0 or j == len(blocks)):
            kind = False
        else:
            kind = zero[i]
        out.append([i * BLOCK, min(j * BLOCK, len(load)), kind])
        i = j
    merged = []
    for a, b, z in out:
        if merged and merged[-1][2] == z:
            merged[-1][1] = b
        else:
            merged.append([a, b, z])
    return [(a, None if z else load[a:b], b - a) for a, b, z in merged]


def payload(load: bytes) -> bytes:
    load += b"\0" * (-len(load) % 4)
    segs = segments(load)
    table, body, total = b"", b"", 0
    for off, data, size in segs:
        table += struct.pack("<2I", RAM + off, size // 4 | (0 if data else ZERO))
        if data:
            body += data
            total += sum(struct.unpack(f"<{len(data) // 4}I", data))
    return struct.pack("<4I", LOAD_MAGIC, len(segs), total & 0xFFFFFFFF, RAM) + table + body


ap = argparse.ArgumentParser(usage=__doc__)
ap.add_argument("boot")
ap.add_argument("out")
ap.add_argument("--pico")
ap.add_argument("--run", type=lambda s: int(s, 0), default=1)
ap.add_argument("loads", nargs="+", metavar="结点号=载荷")
a = ap.parse_args()

boot = pathlib.Path(a.boot).read_bytes()
if len(boot) > DIR - BOOT:
    sys.exit(f"引导程序 {len(boot)} 字节，放不进 64 KiB")
img = bytearray(b"\xff" * DATA)
img[BOOT:BOOT + len(boot)] = boot
if a.pico:
    pico = pathlib.Path(a.pico).read_bytes()
    if len(pico) > DATA - PICO:
        sys.exit(f"PicoRV32 的程序 {len(pico)} 字节，放不进 512 KiB")
    img[PICO:PICO + len(pico)] = pico

where = [0, 0, 0, 0]
for spec in a.loads:
    nodes, _, file = spec.partition("=")
    if not file or not nodes or set(nodes) - set("012"):
        sys.exit(f"{spec}：写成 <结点号…>=<载荷>，结点号是 0、1、2（PicoRV32 的程序用 --pico 给）")
    load = pathlib.Path(file).read_bytes()
    for n in map(int, nodes):
        if where[n]:
            sys.exit(f"{n} 号结点给了两份载荷")
        if len(load) > PRIV[n] - KEEP:
            sys.exit(f"{file} {len(load)} 字节，放不进 {n} 号结点私有的 {PRIV[n] >> 20} MiB（段顶 8 KiB 归引导程序）")
        where[n] = len(img)
    blob = payload(load)
    img += blob + b"\xff" * (-len(blob) % 4)
    print(f"{file}：{len(load)} 字节，{struct.unpack_from('<I', blob, 4)[0]} 段，在 Flash 里占 {len(blob)} 字节，给结点 {nodes}")
if len(img) > END:
    sys.exit(f"镜像 {len(img)} 字节，超过 16 MiB 的 Flash 窗口")
img[DIR:DIR + 24] = struct.pack("<6I", DIR_MAGIC, a.run, *where)
pathlib.Path(a.out).write_bytes(img)
print(f"{a.out}：引导程序 {len(boot)} 字节，共 {len(img)} 字节，0 号结点起来后放开 {a.run:#x}")
