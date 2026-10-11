#!/usr/bin/env bash
# 整片测试，全部跑在 ran asic 出的那份 .v 上。测试台与片外模型来自黑盒仓，测试台的引脚包装来自 to2610-kvc。
#   hello  0 号核从 Flash 就地执行：控制页认得出来，私有段与共享段读写，出了段判出错
# 用法：chip.sh <输出目录> <gf180mcu-kianv-rv32ima-sv32 仓> <to2610-kvc 仓>。
# 已经跑过 ran asic 的，把输出目录给 CHIP_ASIC
set -euo pipefail
cd "$(dirname "$0")/.."
O=$(realpath -m "$1")
K=$(realpath "$2")
L=$(realpath "$3")
rm -rf "$O"
mkdir -p "$O"
A=${CHIP_ASIC:-$O/asic}
[ -s "$A/report.json" ] || $XIRANG asic to2610-noc --no-run -o "$A"
top=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['top'])" "$A/report.json")
python3 "$L/htest/shim.py" "$A/report.json" > "$O/tb.v"
bash "$K/htest/sim.sh" "$O/sim" "$O/tb.v" "$A/$top.v"

res=()
run() {
  local name=$1 what=$2 t0=$SECONDS rc=0
  shift 2
  "$O/sim/Vtb" "$@" > "$O/$name.log" 2> "$O/$name.err" || rc=$?
  tail -n 3 "$O/$name.err"
  res+=("$name=$rc:$((SECONDS - t0)):$what")
}

make -s -C htest/hello O="$O/hello"
run hello "0 号核从 Flash 就地执行：控制页的标识与核号，私有段 1024 个字与字节、半字写，共享段的头尾，出了段判访问出错" \
  +flash="$O/hello/hello.bin@0x100000" +script=htest/hello/script +max=60000000

t0=$SECONDS
rc=0
bash htest/isa.sh "$O/isa" "$O/sim" "$K" > "$O/isa.log" 2>&1 || rc=$?
tail -n 3 "$O/isa.log"
res+=("isa=$rc:$((SECONDS - t0)):riscv-tests 的 rv32ui、uc、um、ua、mi 逐个在这份 .v 上跑，四个核各跑一遍：程序放进那个核私有的那段 SDRAM，0 号核以外的先由 0 号核放开，测试台盯 tohost；不适用的 5 个（Zacas、硬件非对齐访存、PMP、调试触发器）不跑，mcsr 只在 0 号核上跑")

make -s -C htest/box O="$O/box"
run box "四个核一起，同一份程序：信箱空着、发给自己、目的号不存在；放开另外三个核各报到；全对全各 20 个带序号；压着不收时装不下的丢并记一笔；来包的中断与核间中断各叫醒一个睡着的核；收回一个核再放开，它从头来" \
  +flash="$O/box/box.bin@0x100000" +script=htest/box/script +max=200000000

make -s -C htest/atomic O="$O/atomic"
run atomic "四个核在共享段上各加两百次：直接加会丢数，amoadd、amoswap 的自旋锁、带重试的 LR/SC 各得八百且等过、重来过；预留着的字被别的核写了条件写就不成，写的是别的字就成；同一个私有地址四个核各是各的；三个核的计时器按各自设的远近先后到，0 号核的比较值没人动" \
  +flash="$O/atomic/atomic.bin@0x100000" +script=htest/atomic/script +max=400000000

make -s -C sw/boot O="$O/boot"
make -s -C htest/rtos O="$O/rtos" KVC="$L"
python3 sw/pack.py "$O/boot/boot.bin" "$O/rtos/rtos.bin" "$O/rtos.flash"
run rtos "引导程序把同一个镜像搬进各核私有的那段 SDRAM；四个核各起一份 FreeRTOS，另外三个核报到；0 号核的命令行经串口收命令：把 1 到 400 的平方和切成四段派给四个核、收齐相加，问另外三个核的节拍数两次、都在走；最低优先级不让出的任务也转过" \
  +flash="$O/rtos.flash@0" +script=htest/rtos/script +pace=100000 +max=400000000

python3 "$L/htest/junit.py" "$O/results.xml" "${res[@]}"
printf '%s\n' "${res[@]}"
if grep -q '<failure' "$O/results.xml"; then echo "有用例没过"; exit 1; fi
echo "整片测试 ${#res[@]} 段全过"
