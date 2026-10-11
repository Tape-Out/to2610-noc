#!/usr/bin/env bash
# 拼出这一颗的源码树 build/src：黑盒仓拼好的那一份（KianV SoC，即 to2610-kvc 的那一颗）套上 patch/noc.patch
#（拿掉 KianV 核，换成四个结点、四路仲裁、每核一份 CLINT、信箱与控制页），放进 Hazard3 的源码、
# bsc 把 box/NocBox.bsv 连同 noc 库编出来的 Verilog，与本仓 hwsrc 里的几个模块。上游子模块不动。
# 用法：setup.sh <gf180mcu-kianv-rv32ima-sv32 仓> <hazard3 仓> <noc 仓>
set -euo pipefail
cd "$(dirname "$0")/.."
K=$(realpath "$1")
H=$(realpath "$2")/third_party/hazard3/hdl
N=$(realpath "$3")
rm -rf build/src build/box
mkdir -p build/box
bash "$K/htest/setup.sh" > /dev/null
cp -r "$K/build/src" build/src
patch -s -p1 -d build < patch/noc.patch
# 这一颗没有 KianV 核：核的源码不带进来，它目录下 soc.v 用得着的只有头文件与两份通用小件
find build/src/kianv_harris_edition -name '*.v' ! -name 'design_elements*.v' -delete

bsc +RTS -K512m -RTS -verilog -u -vdir build/box -bdir build/box -info-dir build/box \
  -p "box:$N/hwsrc:+" -g mkNocBox box/NocBox.bsv > build/box.log 2>&1 || { tail -n 20 build/box.log; exit 1; }
# bsc 的库模块不落在输出目录，按实例名补齐
B=${XR_BSC_LIB:-$(dirname "$(dirname "$(readlink -f "$(command -v bsc)")")")/lib/Verilog}
for m in $(grep -ohE '^\s+[A-Z][A-Za-z0-9]+ #' build/box/*.v | awk '{print $1}' | sort -u); do
  [ -f "build/box/$m.v" ] || cp "$B/$m.v" build/box/
done
cp build/box/*.v hwsrc/*.v build/src/

mkdir -p build/src/hazard3
cp -r "$H"/*.v "$H"/*.vh "$H"/arith build/src/hazard3/
rm -f build/src/hazard3/hazard3_cpu_2port.v
echo "build/src：$(find build/src -name '*.v' -o -name '*.sv' | wc -l) 个源文件"
