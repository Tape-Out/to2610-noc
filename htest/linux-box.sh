#!/usr/bin/env bash
# 从两份 Linux 都到 shell 的那个断点（build/linux-run/both.ckpt）接着跑：四个结点经信箱与共享段互通。
# 0 号的 Linux 问 Hazard3 的回声，1 号的 Linux 问 PicoRV32 的回声，两份 Linux 互发一个字，共享段上各写一个字、对方读到。
# 两路串口各一份脚本（htest/linux/box.script、box.script1），信箱都经 devmem 读写。
# 用法：linux-box.sh <输出目录> <to2610-kvc 仓>
set -euo pipefail
cd "$(dirname "$0")/.."
O=$(realpath -m "$1")
L=$(realpath "$2")
R=$PWD/build/linux-run
rm -rf "$O"
mkdir -p "$O"
for f in Vtb linux.flash both.ckpt both.ckpt.tb; do
  [ -s "$R/$f" ] || { echo "build/linux-run 里没有 $f：先把 Linux 起到 shell（linux-boot.sh）"; exit 1; }
done
chmod +x "$R/Vtb"
t0=$SECONDS
rc=0
"$R/Vtb" +flash="$R/linux.flash@0" +restore="$R/both.ckpt" +script=htest/linux/box.script +script1=htest/linux/box.script1 \
  +pace=600000 +max=20000000000 +beat=1000000000 > "$O/box.log" 2> "$O/box.err" || rc=$?
tail -n 3 "$O/box.err"
python3 "$L/htest/junit.py" "$O/results.xml" \
  "linux-box=$rc:$((SECONDS - t0)):两份 Linux 都在 shell 里：0 号问 Hazard3 的回声、1 号问 PicoRV32 的回声，回来的都加了一；两份 Linux 经信箱互发一个字，来路与数都对；共享段上各写一个字，对方读到"
exit $rc
