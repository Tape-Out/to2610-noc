#!/usr/bin/env bash
# 整片测试，全部跑在 ran asic 出的那份 .v 上。测试台与片外模型来自黑盒仓，测试台的引脚包装是 htest/shim.py 出的。
# 四个结点是两颗 KianV（0、1 号）、一颗 Hazard3（2 号）、一颗 PicoRV32（3 号）。程序编两份拼进一个 Flash 镜像：
# KianV 与 Hazard3 用公共的 rv32ima 那一份，PicoRV32 的指令集与中断不同，另编一份（htest/pico）。
#   hello   0 号结点从 Flash 就地执行：控制页认得出来，私有段与共享段读写，出了段判出错
#   isa     riscv-tests 四个结点各跑各的一套（htest/isa.sh）
#   box     信箱：四个结点两两互发、堵塞丢包、来包中断与核间中断、收回与放开
#   irq     每个结点的五路中断各点一次
#   atomic  共享段上的原子操作：四种核争用同一个数
#   uart    四个结点各在自己的串口上报一声
#   sig     PicoRV32 的签名指令读出 heke1228
#   rtos    引导程序加 FreeRTOS，PicoRV32 跑一个不带 RTOS 的同口令程序
#   echo    一个镜像里各结点搬各自的载荷
# 两份 Linux 不在这里跑：htest/linux-prep.sh 备料，linux-boot.sh 分几棒起到 shell，linux-box.sh 从断点接着跑
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
python3 htest/shim.py "$A/report.json" > "$O/tb.v"
# 板上是 64 MiB 的 SDRAM：测试台的模型按 10 位列地址编；1 至 3 号结点的串口是测试台多出来的三路
bash "$K/htest/sim.sh" "$O/sim" "$O/tb.v" "$A/$top.v" -CFLAGS "-DSDRAM_COLS=10 -DCONSOLES=3"

res=()
run() {
  local name=$1 what=$2 t0=$SECONDS rc=0
  shift 2
  "$O/sim/Vtb" "$@" > "$O/$name.log" 2> "$O/$name.err" || rc=$?
  tail -n 3 "$O/$name.err"
  res+=("$name=$rc:$((SECONDS - t0)):$what")
}

make -s -C htest/hello O="$O/hello"
run hello "0 号结点从 Flash 就地执行：控制页的标识与核号，私有段 1024 个字与字节、半字写，共享段的头尾，出了段判访问出错" \
  +flash="$O/hello/hello.bin@0x100000" +script=htest/hello/script +max=60000000

t0=$SECONDS
rc=0
bash htest/isa.sh "$O/isa" "$O/sim" "$K" > "$O/isa.log" 2>&1 || rc=$?
tail -n 3 "$O/isa.log"
res+=("isa=$rc:$((SECONDS - t0)):riscv-tests 四个结点各跑各的一套：两颗 KianV 各是 rv32ui、um、ua、mi、si 加一条 AMO 写半边缺页的定向测试，Hazard3 是 rv32ui、uc、um、ua、mi，PicoRV32 是 rv32ui、uc、um、ua（A 扩展与 fence.i 由协处理器补）；程序放进那个结点私有的那段 SDRAM，0 号以外的先由 0 号放开，测试台盯 tohost；不适用的 5 个（Zacas、硬件非对齐访存、PMP、调试触发器）不跑")

make -s -C htest/box O="$O/box"
run box "四个结点一起：信箱空着、发给自己、目的号不存在；放开另外三个结点各报到；全对全各 20 个带序号；压着不收时装不下的丢并记一笔；来包的中断叫醒睡着的 Hazard3，核间中断叫醒睡着的 PicoRV32；收回一个结点再放开，它从头来" \
  +flash="$O/box/box.bin@0x100000" +script=htest/box/script +max=200000000

make -s -C htest/irq O="$O/irq"
run irq "每个结点把自己的五路中断各点一次：计时器、软件中断、信箱来包、核间中断、串口，共二十路；中断里按核认到的来路核对，KianV 是 mcause 加向 PLIC 认领的源号，PicoRV32 是入口给的位图" \
  +flash="$O/irq/irq.bin@0x100000" +script=htest/irq/script +max=60000000

make -s -C htest/atomic O="$O/atomic"
run atomic "四种核在共享段上各加两百次：直接加会丢数，amoadd、amoswap 的自旋锁、带重试的 LR/SC 各得八百且等过、重来过；预留着的字被别的结点写了条件写就不成，写的是别的字就成；同一个私有地址四个结点各是各的；三个结点的计时器按各自设的远近先后到，0 号的比较值没人动" \
  +flash="$O/atomic/atomic.bin@0x100000" +script=htest/atomic/script +max=400000000

make -s -C htest/uart O="$O/uart"
run uart "每个结点一路串口：四个结点各在自己的串口上报一声，四路各有一份脚本等那个结点自己的那一句，一路上多出别的字也算不过" \
  +flash="$O/uart/uart.bin@0x100000" +script=htest/uart/script +script1=htest/uart/script1 +script2=htest/uart/script2 \
  +script3=htest/uart/script3 +max=60000000
# 一路上只许有那个结点自己的那一句：别的结点的字漏过来，多出来的行也算不过
for i in 1 2 3; do
  got=$(grep -a "^\[uart$i\]" "$O/uart.log" | tr -d '\r' || true)
  [ "$got" != "[uart$i] node $i here" ] || continue
  echo "$i 号结点的串口上不是它自己的那一句：$(head -n 3 <<< "$got" | tr '\n' '|')"
  res[-1]="uart=1:${res[-1]#*:}"
done

make -s -C htest/sig O="$O/sig"
run sig "PicoRV32 的签名指令（custom-1）：读到的两个字经信箱交给 0 号结点，串口打出 heke1228；rs1 取别的数读到 0，custom-1 的别的编码报非法指令" \
  +flash="$O/sig/sig.bin@0x100000" +script=htest/sig/script +max=60000000

make -s -C sw/boot O="$O/boot"
make -s -C htest/rtos O="$O/rtos" KVC="$L"
python3 sw/pack.py "$O/boot/boot.bin" "$O/rtos.flash" --pico "$O/rtos/pico.bin" 012="$O/rtos/rtos.bin"
run rtos "引导程序照目录把同一份载荷搬进 KianV 与 Hazard3 各自私有的那段 SDRAM，三个结点各起一份 FreeRTOS，堆是各段之后到段顶的那一截（KianV 的 23 MiB，Hazard3 的 3 MiB）；PicoRV32 就地跑一个不带 RTOS 的同口令程序，没活时等中断；0 号结点的命令行经串口收命令：把 1 到 400 的平方和切成四段派给四个结点、收齐相加，问另外三个结点的节拍数两次、都在走；最低优先级不让出的任务也转过" \
  +flash="$O/rtos.flash@0" +script=htest/rtos/script +pace=100000 +max=400000000

make -s -C htest/echo O="$O/echo"
python3 sw/pack.py "$O/boot/boot.bin" "$O/echo.flash" --pico "$O/echo/pico.bin" --run 0xd 0="$O/echo/master.bin" 2="$O/echo/echo.bin"
run echo "一个镜像里各结点搬各自的那一份：0 号是发问的程序，Hazard3 是回声，PicoRV32 的回声就地跑；0 号的引导程序照目录先放开那两个结点，再给两个回声各发八个数，回来的都加了一、来路对" \
  +flash="$O/echo.flash@0" +script=htest/echo/script +script2=htest/echo/script2 +max=60000000

python3 "$L/htest/junit.py" "$O/results.xml" "${res[@]}"
printf '%s\n' "${res[@]}"
if grep -q '<failure' "$O/results.xml"; then echo "有用例没过"; exit 1; fi
echo "整片测试 ${#res[@]} 段全过"
