#!/usr/bin/env bash
# 设计这一层的变异：把仲裁、信箱、CLINT 的排法里的一处改错，重出 .v，四核的那两段测试里管这一处的那一句要红。
# 脚本里的 expect 都拿掉、只留 done，让程序跑到底，看是哪几句红了；跑到一半卡住、该红的那一句还没报 ok，也算抓到。
# 在临时的工作区里做（别的仓软链接过来，本仓拷一份），不动真的仓。
# 用法：design-faults.sh <输出目录> <gf180mcu-kianv-rv32ima-sv32 仓> <to2610-kvc 仓>      FAULTS=名字,名字 只跑表里的这几条
set -u
cd "$(dirname "$0")/.."
here=$PWD
O=$(realpath -m "$1")
K=$(realpath "$2")
L=$(realpath "$3")
rm -rf "$O"
mkdir -p "$O/ws/to2610-noc"
# 照这次息壤的搜索路径去链：流水线上各个依赖不在本仓旁边
for r in $(grep -o -- '-p [^ ]*' <<< "$XIRANG" | cut -c4-) "$here/.."; do
  for d in "$r"/*/; do
    n=$(basename "$d")
    [ "$n" = to2610-noc ] || [ -e "$O/ws/$n" ] || ln -s "$(realpath "$d")" "$O/ws/$n"
  done
done
tar cf - --exclude=build --exclude=.git . | tar xf - -C "$O/ws/to2610-noc"
RAN="${XIRANG%% -p *} -p $O/ws"
R=$O/ws/to2610-noc

make -s -C htest/box O="$O/box" || exit 1
make -s -C htest/atomic O="$O/atomic" || exit 1
echo "expect done" > "$O/script"

# 名字~改哪个文件~sed 表达式~跑哪一段~该红的那一句（* 是哪一句红都算）。表达式里不能出现分隔用的那个波浪号
TABLE='window~hwsrc/noc_arb.v~s/cur == 2.d1 ? 32.h8060_0000/cur == 2'"'"'d1 ? 32'"'"'h8000_0000/~box~*
stale~hwsrc/noc_arb.v~s/for (k = 0; k < 4; k = k + 1) if (rsv_a\[k\] == pa\[31:2\]) rsv_v\[k\] <= 1.b0;/rsv_v[own] <= 1'"'"'b0;/~atomic~reserve
nak~hwsrc/noc_arb.v~s/over ? BAD : (ex \&\& wr \&\& !held) ? NAK : BUS;/over ? BAD : BUS;/~atomic~reserve
keep~hwsrc/noc_arb.v~s/else if (!(st != IDLE \&\& own == k)) go\[k\] <= 1.b0;/else go[k] <= go[k];/~box~again
src~box/NocBox.bsv~s/src: fromInteger(i), payload: wdata/src: 0, payload: wdata/~box~up
drop~box/NocBox.bsv~s/else dropped\[i\] <= True;/else noAction;/~box~drop
nowhere~box/NocBox.bsv~s/if (dest\[i\] >= fromInteger(valueOf(Nodes))) nowhere\[i\] <= True;/if (False) nowhere[i] <= True;/~box~self
rxirq~box/NocBox.bsv~s/v\[i\] = pack(rxq\[i\].notEmpty \&\& ie\[i\]);/v[i] = 0;/~box~irq
ipiack~box/NocBox.bsv~s/4: ipiR <= ipiR \& .me;/4: noAction;/~box~ipi
slot~patch/noc.patch~s/c_at == 24.h00_4000 + 8 \* ci ?/c_at == 24'"'"'h00_4000 ?/~atomic~timer'

# 出 .v、编仿真器、跑那一段，回哪几句 BAD（空格隔开）；没跑到 done 的后面跟 stuck 与报了 ok 的那几句（ok:名字）
one() {
  local C=$1 prog=$2 top stuck=
  rm -rf "$C" && mkdir -p "$C"
  (cd "$R" && $RAN asic to2610-noc --no-run -o "$C/asic" > "$C/asic.log" 2>&1) || { echo "出 .v 没成：$(tail -n 2 "$C/asic.log" | tr '\n' ' ')"; return 1; }
  top=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['top'])" "$C/asic/report.json")
  python3 "$L/htest/shim.py" "$C/asic/report.json" > "$C/tb.v"
  bash "$K/htest/sim.sh" "$C/sim" "$C/tb.v" "$C/asic/$top.v" > "$C/sim.log" 2>&1 || { echo "仿真器没编成"; return 1; }
  "$C/sim/Vtb" +flash="$O/$prog/$prog.bin@0x100000" +script="$O/script" +max=60000000 > "$C/run.log" 2> "$C/run.err" || stuck=1
  tr -d '\r' < "$C/run.log" | awk '$2 == "BAD" {printf "%s ", $1}'
  [ -z "$stuck" ] || { printf 'stuck '; tr -d '\r' < "$C/run.log" | awk '$2 == "ok" {printf "ok:%s ", $1}'; }
}

for prog in box atomic; do
  got=$(one "$O/clean-$prog" "$prog")
  rc=$?
  if [ $rc -ne 0 ] || [ -n "$got" ]; then
    echo "原样的 $prog 没过：$got"
    exit 1
  fi
  echo "原样的 $prog：$(tr -d '\r' < "$O/clean-$prog/run.log" | grep -ac ' ok ') 句都是 ok"
done

bad=0
count=0
while IFS='~' read -r name file expr prog want; do
  case ",${FAULTS:-$name}," in *",$name,"*) ;; *) continue ;; esac
  count=$((count + 1))
  sed -e "$expr" "$file" > "$R/$file"
  if cmp -s "$file" "$R/$file"; then
    echo "$name 没埋上"
    bad=1
    continue
  fi
  got=$(one "$O/mut-$name" "$prog")
  rc=$?
  cp "$file" "$R/$file"
  red=${got%%stuck*}
  if [ $rc -ne 0 ]; then
    echo "$name：$got"
    bad=1
  elif [ "$want" = "*" ] && { [ -n "$red" ] || [[ $got == *stuck* ]]; }; then
    echo "$name 红了：${red:-跑到一半卡住}"
  elif [ "$want" != "*" ] && grep -qw -- "$want" <<< "$red"; then
    echo "$name 红了：$red"
  elif [ "$want" != "*" ] && [[ $got == *stuck* ]] && ! grep -qw -- "ok:$want" <<< "$got"; then
    echo "$name 红了：跑到一半卡住，$want 那一句没报 ok"
  else
    echo "$name 改错了，$want 那一句没红（红的是：${got:-没有}）"
    bad=1
  fi
done <<< "$TABLE"
[ $bad -eq 0 ] || { echo "有改错的地方没被抓到"; exit 1; }
echo "设计的变异：原样过，$count 处改错都红在该红的那一句上"
