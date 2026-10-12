#!/usr/bin/env bash
# 给两份 Linux 的接力备料，放进 build/linux-run：编好的仿真器、拼好的 Flash 镜像、两路串口的脚本。不跑测试，十来分钟；
# 之后 htest/linux-boot.sh 分几棒把两份 Linux 起到 shell，htest/linux-box.sh 从那个断点接着跑。
# 镜像取 to2610-kvc 钉住的那一份（LINUX_IMAGE 给了本机已有的、摘要对得上就不取），sw/linux-image.py 把设备树里的
# 内存改成 24 MiB；两颗 KianV 共用它，Hazard3 与 PicoRV32 两个结点跑回声（htest/echo）。
# 用法：linux-prep.sh <输出目录> <gf180mcu-kianv-rv32ima-sv32 仓> <to2610-kvc 仓>。已经跑过 ran asic 的，把输出目录给 CHIP_ASIC
set -euo pipefail
cd "$(dirname "$0")/.."
O=$(realpath -m "$1")
K=$(realpath "$2")
L=$(realpath "$3")
R=$PWD/build/linux-run
rm -rf "$O" "$R"
mkdir -p "$O" "$R"
A=${CHIP_ASIC:-$O/asic}
[ -s "$A/report.json" ] || $XIRANG asic to2610-noc --no-run -o "$A"
top=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['top'])" "$A/report.json")
python3 htest/shim.py "$A/report.json" > "$O/tb.v"
bash "$K/htest/sim.sh" "$O/sim" "$O/tb.v" "$A/$top.v" -CFLAGS "-DSDRAM_COLS=10 -DCONSOLES=3"

IMG=${LINUX_IMAGE:-build/linux/fw_payload.bin}
read -r url sum < "$L/sw/linux/image.pin"
if ! echo "$sum  $IMG" | sha256sum -c - > /dev/null 2>&1; then
  mkdir -p "$(dirname "$IMG")"
  curl -fsSL --retry 5 -o "$IMG.part" "$url"
  echo "$sum  $IMG.part" | sha256sum -c - > /dev/null || { echo "取到的镜像摘要不是 $sum"; exit 1; }
  mv "$IMG.part" "$IMG"
fi
python3 sw/linux-image.py "$IMG" "$O/fw_noc.bin"
make -s -C sw/boot O="$O/boot"
make -s -C htest/echo O="$O/echo"
python3 sw/pack.py "$O/boot/boot.bin" "$R/linux.flash" --pico "$O/echo/pico.bin" --run 0xf 01="$O/fw_noc.bin" 2="$O/echo/echo.bin"
cp "$O/sim/Vtb" htest/linux/script htest/linux/script1 "$R/"
python3 "$L/htest/junit.py" "$O/results.xml" \
  "linux-prep=0:$SECONDS:to2610-kvc 钉住的那份镜像（$(basename "$(dirname "$url")")），设备树里的内存改成 24 MiB，连同 Hazard3 与 PicoRV32 的回声拼成一个 Flash 镜像，与编好的仿真器一起备给后面的接力"
ls -la "$R"
