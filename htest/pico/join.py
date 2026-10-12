"""把两份程序拼成一份放进 Flash：前一份给 KianV 与 Hazard3（复位向量 0x2010_0000），
后一份给 PicoRV32（0x2018_0000，在前一份之后 512 KiB）。用法：join.py <前一份> <后一份> <输出>"""
import pathlib
import sys

GAP = 0x80000
a = pathlib.Path(sys.argv[1]).read_bytes()
b = pathlib.Path(sys.argv[2]).read_bytes()
assert len(a) <= GAP, f"前一份有 {len(a)} 字节，超过 {GAP}"
pathlib.Path(sys.argv[3]).write_bytes(a.ljust(GAP, b"\xff") + b)
