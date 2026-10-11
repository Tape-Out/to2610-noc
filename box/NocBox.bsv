package NocBox;

import Vector::*;
import GetPut::*;
import FIFOF::*;
import Noc::*;

// 四个核各一份信箱，背后是一张 2×2 网格，再加一页控制寄存器。挂在仲裁之后的那条总线上，
// 总线带着这一次访问是哪个核发的：信箱那一页按它选，四个核在同一个地址上各看到自己的一份。
//
//   0x000 ID      只读，0x4E4F4334（"NOC4"）
//   0x004 HART    只读，发这次访问的核号
//   0x008 RUN     第 i 位放开第 i 个核的复位；第 0 位恒为 1
//   0x00C IPI     写 1 的位给对应的核挂一个核间中断；读回四个核挂着的
//   0x010 IPIACK  写任意值，清掉自己的那一位
//   0x100 TXDEST  目的结点号
//   0x104 TXDATA  写即发，源结点号由硬件填；网格不收或目的号不存在就丢，记在 STAT
//   0x108 RXSRC   队头那个包的源结点号
//   0x10C RXDATA  队头那个包的载荷，读即出队；空的时候读到 0
//   0x110 STAT    位 0 收到了，位 1 可发，位 2 发的时候丢过，位 3 目的号不存在；位 2、3 写 1 清
//   0x114 IE      位 0：收到包时报外部中断
//
// 发送不等人：网格堵着的时候写 TXDATA 不会把核卡在总线上，丢了由软件看 STAT 重发。
// 四个核都卡在发送上、谁也腾不出手来收的那种死锁就不会有。

interface NocBoxIfc;
  (* always_ready, always_enabled, prefix = "" *)
  method Action bus((* port = "bus_valid_i" *) Bool valid, (* port = "bus_owner_i" *) UInt#(2) owner,
                    (* port = "bus_addr_i" *) Bit#(9) addr, (* port = "bus_write_i" *) Bool write,
                    (* port = "bus_wdata_i" *) Bit#(32) wdata);
  (* always_ready, result = "bus_rdata_o" *) method Bit#(32) rdata;
  (* always_ready, result = "bus_ready_o" *) method Bool ready;
  (* always_ready, result = "run" *) method Bit#(4) run;
  (* always_ready, result = "irq" *) method Bit#(4) irq;
  (* always_ready, result = "ipi" *) method Bit#(4) ipi;
endinterface

typedef 4 Nodes;
typedef Pkt#(32) Msg;

(* synthesize *)
module mkNocBox(NocBoxIfc);
  Mesh#(2, 2) mesh = Mesh;
  Network#(Nodes, 32) net <- mkNetwork(mesh);

  Vector#(Nodes, FIFOF#(Msg)) txq <- replicateM(mkUGFIFOF);
  Vector#(Nodes, FIFOF#(Msg)) rxq <- replicateM(mkUGSizedFIFOF(4));

  Vector#(Nodes, Reg#(UInt#(8))) dest    <- replicateM(mkReg(0));
  Vector#(Nodes, Reg#(Bool))     dropped <- replicateM(mkReg(False));
  Vector#(Nodes, Reg#(Bool))     nowhere <- replicateM(mkReg(False));
  Vector#(Nodes, Reg#(Bool))     ie      <- replicateM(mkReg(False));

  Reg#(Bit#(4))  runR   <- mkReg(4'b0001);
  Reg#(Bit#(4))  ipiR   <- mkReg(0);
  Reg#(Bool)     readyR <- mkReg(False);
  Reg#(Bit#(32)) rdataR <- mkReg(0);

  for (Integer i = 0; i < valueOf(Nodes); i = i + 1) begin
    rule pump (txq[i].notEmpty);
      net.inject[i].put(txq[i].first);
      txq[i].deq;
    endrule

    rule fill (rxq[i].notFull);
      let p <- net.deliver[i].get;
      rxq[i].enq(p);
    endrule
  end

  method Action bus(Bool valid, UInt#(2) owner, Bit#(9) addr, Bool write, Bit#(32) wdata);
    // 应答的那一拍请求还顶着，不能当成下一次
    Bool go = valid && !readyR;
    Bool box = addr[8] == 1;
    Bit#(6) sel = addr[7:2];
    Bit#(4) me = 1 << owner;

    Bool has = False;
    Bool room = False;
    Msg head = unpack(0);
    for (Integer i = 0; i < valueOf(Nodes); i = i + 1)
      if (owner == fromInteger(i)) begin
        has = rxq[i].notEmpty;
        room = txq[i].notFull;
        head = rxq[i].first;
      end

    Bit#(32) r = 0;
    if (!box)
      case (sel)
        0: r = 32'h4E4F_4334;
        1: r = zeroExtend(pack(owner));
        2: r = zeroExtend(runR);
        3: r = zeroExtend(ipiR);
      endcase
    else
      case (sel)
        0: r = zeroExtend(pack(dest[owner]));
        2: r = has ? zeroExtend(pack(head.src)) : 0;
        3: r = has ? head.payload : 0;
        4: r = zeroExtend({pack(nowhere[owner]), pack(dropped[owner]), pack(room), pack(has)});
        5: r = zeroExtend(pack(ie[owner]));
      endcase

    readyR <= go;
    if (go) begin
      rdataR <= r;
      if (!box && write)
        case (sel)
          2: runR <= wdata[3:0] | 4'b0001;
          3: ipiR <= ipiR | wdata[3:0];
          4: ipiR <= ipiR & ~me;
        endcase
      for (Integer i = 0; i < valueOf(Nodes); i = i + 1)
        if (box && owner == fromInteger(i)) begin
          if (write)
            case (sel)
              0: dest[i] <= unpack(wdata[7:0]);
              1: if (dest[i] >= fromInteger(valueOf(Nodes))) nowhere[i] <= True;
                 else if (room) txq[i].enq(Pkt { dest: dest[i], src: fromInteger(i), payload: wdata });
                 else dropped[i] <= True;
              4: begin
                   if (wdata[2] == 1) dropped[i] <= False;
                   if (wdata[3] == 1) nowhere[i] <= False;
                 end
              5: ie[i] <= wdata[0] == 1;
            endcase
          else if (sel == 3 && has)
            rxq[i].deq;
        end
    end
  endmethod

  method Bit#(32) rdata = rdataR;
  method Bool ready = readyR;
  method Bit#(4) run = runR;

  method Bit#(4) irq;
    Bit#(4) v = 0;
    for (Integer i = 0; i < valueOf(Nodes); i = i + 1)
      v[i] = pack(rxq[i].notEmpty && ie[i]);
    return v;
  endmethod

  method Bit#(4) ipi = ipiR;
endmodule

endpackage
