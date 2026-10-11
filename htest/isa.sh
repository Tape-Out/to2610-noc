#!/usr/bin/env bash
# 标准 riscv-tests 的 p 环境，在交付的 .v 上四个核各跑一遍。程序直接放进那个核私有的那段 SDRAM，
# Flash 里是一小段跳转（htest/isa/jump.S：0 号核以外的要先由 0 号核放开），测试台盯 tohost。
# 用法：isa.sh <输出目录> <编好的 Vtb 所在目录> <gf180mcu-kianv-rv32ima-sv32 仓（取它带的 riscv-tests）>
set -euo pipefail
cd "$(dirname "$0")/.."
O=$(realpath -m "$1")
SIM=$(realpath "$2")
R=$(realpath "$3")/third_party/riscv-tests
X=${CROSS:-riscv64-unknown-elf-}
[ -f "$R/env/p/link.ld" ] || { echo "riscv-tests 的子模块没取：git submodule update --init --recursive"; exit 1; }
mkdir -p "$O"

# 不适用的不跑：Zacas 不是 A 本身；硬件非对齐访存、PMP、调试触发器这一颗都没开
SKIP=" rv32ua-p-amocas_w rv32ua-p-amocas_d rv32ui-p-ma_data rv32mi-p-pmpaddr rv32mi-p-breakpoint "

n=0; bad=0
for s in rv32ui rv32uc rv32um rv32ua rv32mi; do
  for t in "$R"/isa/$s/*.S; do
    b=$s-p-$(basename "$t" .S)
    [[ $SKIP == *" $b "* ]] && continue
    e="$O/$b"
    # -fno-pic：Linux 工具链默认位置无关，env 里的 la 会出 GOT 重定位
    "${X}gcc" -march=rv32imac_zicsr_zifencei -mabi=ilp32 -static -mcmodel=medany -fvisibility=hidden \
      -nostdlib -nostartfiles -fno-pic -no-pie -I htest/isa/env -I "$R/env/p" -I "$R/isa/macros/scalar" \
      -T "$R/env/p/link.ld" "$t" -o "$e.elf"
    "${X}objcopy" -O binary "$e.elf" "$e.bin"
    host=$((0x$("${X}nm" "$e.elf" | awk '$3 == "tohost" {print $1}')))
    for c in 0 1 2 3; do
      # mcsr 的第 3 项核对 mhartid 读到 0，只对 0 号核成立
      [ "$b" = rv32mi-p-mcsr ] && [ $c != 0 ] && continue
      if [ ! -s "$O/jump$c.bin" ]; then
        "${X}gcc" -march=rv32imac_zicsr -mabi=ilp32 -nostdlib -DCORE=$c -Wl,-Ttext=0x20100000 -o "$O/jump$c.elf" htest/isa/jump.S
        "${X}objcopy" -O binary "$O/jump$c.elf" "$O/jump$c.bin"
      fi
      n=$((n + 1))
      # 第 c 个核的私有段在 SDRAM 里从 c × 6 MiB 起
      off=$((c * 0x600000))
      "$SIM/Vtb" +flash="$O/jump$c.bin@0x100000" +sdram="$e.bin@$off" +tohost="$(printf '0x%x' $((host + off)))" \
        +max=8000000 > "$e.$c.log" 2>&1 || { echo "FAIL $b 在 $c 号核上：$(grep -a 'tohost' "$e.$c.log" | tail -n 1)"; bad=$((bad + 1)); }
    done
  done
done

echo "四个核共跑 $n 次，$bad 次不过，不适用 $(wc -w <<< "$SKIP") 个"
[ "$n" -gt 0 ] && [ "$bad" = 0 ]
