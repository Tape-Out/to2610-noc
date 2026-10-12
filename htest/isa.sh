#!/usr/bin/env bash
# 标准 riscv-tests 在交付的 .v 上四个结点各跑各的一套。程序直接放进那个结点私有的那段 SDRAM，
# Flash 里是一小段跳转（htest/isa/jump.S：0 号以外的要先由 0 号放开），测试台盯 tohost。
#   0、1 号  KianV：黑盒仓的那一套（p 环境，rv32ui、um、ua、mi、si，加它自写的定向测试），0 号直接调它的 isa.sh
#   2 号     Hazard3：p 环境，rv32ui、uc、um、ua、mi
#   3 号     PicoRV32：没有机器态的 CSR，用 htest/isa/env-pico 的环境，rv32ui、uc、um、ua（A 扩展是协处理器补的）
# 用法：isa.sh <输出目录> <编好的 Vtb 所在目录> <gf180mcu-kianv-rv32ima-sv32 仓（取它带的 riscv-tests）>
set -euo pipefail
cd "$(dirname "$0")/.."
O=$(realpath -m "$1")
SIM=$(realpath "$2")
K=$(realpath "$3")
R=$K/third_party/riscv-tests
X=${CROSS:-riscv64-unknown-elf-}
[ -f "$R/env/p/link.ld" ] || { echo "riscv-tests 的子模块没取：git submodule update --init --recursive"; exit 1; }
mkdir -p "$O"

# 各结点私有段在 SDRAM 里从哪起：与 patch/mkpatch.py 里给仲裁的那组大小同一组数
OFF=(0 $((0x1800000)) $((0x3000000)) $((0x3400000)))
# 不适用的不跑：Zacas 不是 A 本身；硬件非对齐访存、PMP、调试触发器这一颗都没开
SKIP=" rv32ua-p-amocas_w rv32ua-p-amocas_d rv32ui-p-ma_data rv32mi-p-pmpaddr rv32mi-p-breakpoint "

n=0; bad=0
# $1 结点号，$2 用例名，$3 源文件，其后是给编译器的选项（指令集与环境头的目录）
one() {
  local c=$1 b=$2 t=$3 e="$O/$2.$1" host
  shift 3
  [[ $SKIP == *" $b "* ]] && return
  # -fno-pic：Linux 工具链默认位置无关，env 里的 la 会出 GOT 重定位
  "${X}gcc" "$@" -mabi=ilp32 -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles -fno-pic -no-pie \
    -I "$R/isa/macros/scalar" -T "$R/env/p/link.ld" "$t" -o "$e.elf"
  "${X}objcopy" -O binary "$e.elf" "$e.bin"
  host=$((0x$("${X}nm" "$e.elf" | awk '$3 == "tohost" {print $1}')))
  n=$((n + 1))
  "$SIM/Vtb" +flash="$O/jump$c.bin@0x100000" +sdram="$e.bin@${OFF[$c]}" +tohost="$(printf '0x%x' $((host + OFF[c])))" \
    +max=8000000 > "$e.log" 2>&1 || { echo "FAIL $b 在 $c 号结点上：$(grep -a 'tohost' "$e.log" | tail -n 1)"; bad=$((bad + 1)); }
}

# 跳板：前一份给 KianV 与 Hazard3，后一份给 PicoRV32，拼成一个镜像
"${X}gcc" -march=rv32imc -mabi=ilp32 -nostdlib -DPICO -Wl,-Ttext=0x20180000 -o "$O/jumpp.elf" htest/isa/jump.S
"${X}objcopy" -O binary "$O/jumpp.elf" "$O/jumpp.bin"
for c in 1 2 3; do
  "${X}gcc" -march=rv32ima_zicsr -mabi=ilp32 -nostdlib -DCORE=$c -Wl,-Ttext=0x20100000 -o "$O/jump$c.elf" htest/isa/jump.S
  "${X}objcopy" -O binary "$O/jump$c.elf" "$O/jump$c.raw"
  python3 htest/pico/join.py "$O/jump$c.raw" "$O/jumpp.bin" "$O/jump$c.bin"
done

# 0 号结点：它的私有段就在 SDRAM 的开头，黑盒仓的 isa.sh 原样用
rc=0
SIM="$SIM" bash "$K/htest/isa.sh" "$O/kv0" > "$O/kv0.log" 2>&1 || rc=$?
tail -n 1 "$O/kv0.log"
[ $rc = 0 ] || { grep -a '^FAIL' "$O/kv0.log" | head -n 5; bad=$((bad + 1)); }
k0=$(sed -n 's/^跑 \([0-9]*\) 个.*/\1/p' "$O/kv0.log" | tail -n 1)
[ -n "$k0" ] || { echo "0 号结点那一套没跑起来"; exit 1; }

for s in rv32ui rv32um rv32ua rv32mi rv32si; do
  for t in "$R"/isa/$s/*.S; do
    one 1 "$s-p-$(basename "$t" .S)" "$t" -march=rv32ima_zicsr_zifencei -I "$R/env/p"
  done
done
for t in "$K"/htest/isa/*.S; do
  one 1 "own-p-$(basename "$t" .S)" "$t" -march=rv32ima_zicsr_zifencei -I "$R/env/p"
done
for s in rv32ui rv32uc rv32um rv32ua rv32mi; do
  for t in "$R"/isa/$s/*.S; do
    one 2 "$s-p-$(basename "$t" .S)" "$t" -march=rv32imac_zicsr_zifencei -I htest/isa/env -I "$R/env/p"
  done
done
for s in rv32ui rv32uc rv32um rv32ua; do
  for t in "$R"/isa/$s/*.S; do
    one 3 "$s-p-$(basename "$t" .S)" "$t" -march=rv32imac_zifencei -I htest/isa/env-pico
  done
done

echo "四个结点共跑 $((n + k0)) 次（0 号 $k0，另三个 $n），$bad 次不过，不适用 $(wc -w <<< "$SKIP") 个"
[ "$n" -gt 0 ] && [ "$bad" = 0 ]
