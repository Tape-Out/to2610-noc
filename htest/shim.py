"""照 report.json 的位表写测试台要的 tb：前 54 位焊盘经它接到黑盒仓的测试台上（与 to2610-kvc 的那一份相同），
后面 1 至 3 号结点的三路串口接到测试台多出来的那几路上：con_rx 是往芯片发的，con_tx 是芯片发出来的，
各有各的脚本（+script1= 起），收到的字按行加上「[uartN]」打进日志。

位表只写在 report.json 里一处，这里照着它生成，不另写一份。
"""
import json
import re
import sys

rep = json.load(open(sys.argv[1], encoding="utf-8"))
W = rep["pads"]["width"]
KVC = 54


def pad(role: str, name: str) -> int:
    m = re.fullmatch(rf"bidir_{role}\[(\d+)\]", name)
    assert m, name
    return int(m.group(1))


ins, outs = {}, []
for b in rep["pads"]["bits"]:
    if b["in"]:
        k = pad("in", b["in"])
        # 54、56、58 是 1、2、3 号结点的 RX；TX 那几根脚的输入没人看，按空闲的高电平接
        ins[b["bit"]] = f"pad_in[{k}]" if k < KVC else f"con_rx[{(k - KVC) // 2}]" if k % 2 == 0 else "1'b1"
    for role in ("out", "oe"):
        if b[role]:
            k = pad(role, b[role])
            if k < KVC:
                outs.append(f"  assign pad_{role}[{k}] = io_{role}[{b['bit']}];")
            elif role == "out" and k % 2:
                # 55、57、59 是 1、2、3 号结点的 TX
                outs.append(f"  assign con_tx[{(k - KVC) // 2}] = io_out[{b['bit']}];")
io_in = ", ".join(ins.get(i, "1'b0") for i in range(W - 1, -1, -1))
print(f"""// 由 htest/shim.py 照 report.json 生成
module tb (
  input  wire        clk,
  input  wire        rst_n,
  input  wire [{KVC - 1}:0] pad_in,
  output wire [{KVC - 1}:0] pad_out,
  output wire [{KVC - 1}:0] pad_oe,
  input  wire [ 2:0] con_rx,
  output wire [ 2:0] con_tx
);
  wire [{W - 1}:0] io_out, io_oe;
  wire [{W - 1}:0] io_in = {{{io_in}}};
{chr(10).join(outs)}
  {rep["top"]} chip (.clock(clk), .reset(~rst_n), .io_in(io_in), .io_out(io_out), .io_oe(io_oe));
endmodule
""")
