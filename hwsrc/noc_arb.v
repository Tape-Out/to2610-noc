// 四个核共用 KianV 的那条片上总线：片外的 Flash、SDRAM 与外设只有一份。
//
// 轮转：一次访问从举手到应答做完才换人，下一次从刚用完的那个核的下一个找起。片上几个外设的应答在请求
// 撤掉之后还要高一拍，所以每次做完空三拍再放下一个。没在访问时地址、写选通、指令标记都给 0：外设区的
// 应答是照上一拍的地址预先算的，漏出去的地址会让下一次访问第一拍就被当成做完。
//
// 各核看到的地址相同，落到 SDRAM 上各是各的：
//   0x8000_0000 起 6 MiB  私有，物理上按核号错开，别的核碰不到
//   0x9000_0000 起 8 MiB  共享，排在四段私有的后面
// 越出这两段的 0x8、0x9 开头的地址在这里就判访问出错，不上总线。
//
// 独占访问（LR、SC 与 AMO）的预留表也在这里，按物理地址记，每核一条：
//   独占读做完，记下这个核预留了哪个字；
//   独占写上总线之前查表，预留还在才写，不在就不上总线、直接回「没写成」；
//   任何一个核写成了一个字，所有预留着这个字的条目作废。
//
// 收回一个核要等它手上那一次访问做完：访问到一半撤掉请求，SDRAM 那头还会把它做完，应答就落到下一次头上。
`default_nettype none
module noc_arb (
    input  wire         clk,
    input  wire         resetn,

    input  wire [  3:0] m_valid,
    input  wire [ 15:0] m_wstrb,
    input  wire [127:0] m_addr,
    input  wire [127:0] m_wdata,
    input  wire [  3:0] m_instr,
    input  wire [  3:0] m_excl,
    output wire [  3:0] m_ready,
    output wire [  3:0] m_fault,
    output wire         m_exokay,

    input  wire [  3:0] run,
    output reg  [  3:0] go,

    output wire         valid,
    output wire [  3:0] wstrb,
    output wire [ 33:0] addr,
    output wire [ 31:0] wdata,
    output wire         instr,
    output wire [  1:0] owner,
    input  wire         ready,
    input  wire         fault
);
  localparam [1:0] IDLE = 2'd0, BUS = 2'd1, NAK = 2'd2, BAD = 2'd3;
  localparam [31:0] PRIV = 32'h0060_0000, SHARE = 32'h0080_0000;

  reg [ 1:0] st, own, last, cool;
  reg [ 3:0] rsv_v;
  reg [29:0] rsv_a  [0:3];

  // 从 last 的下一个起，第一个举手的
  wire [1:0] n1 = last + 2'd1, n2 = last + 2'd2, n3 = last + 2'd3;
  wire       any = |m_valid;
  wire [1:0] pick = m_valid[n1] ? n1 : m_valid[n2] ? n2 : m_valid[n3] ? n3 : last;
  wire [1:0] cur = st == IDLE ? pick : own;

  wire [31:0] la = m_addr[cur*32+:32];
  wire [ 3:0] ls = m_wstrb[cur*4+:4];
  wire        is_priv = la[31:28] == 4'h8;
  wire        is_share = la[31:28] == 4'h9;
  wire [27:0] off = la[27:0];
  wire        over = (is_priv && {4'h0, off} >= PRIV) || (is_share && {4'h0, off} >= SHARE);
  wire [31:0] base = is_share ? 32'h8180_0000 : cur == 2'd0 ? 32'h8000_0000 : cur == 2'd1 ? 32'h8060_0000 :
                     cur == 2'd2 ? 32'h80C0_0000 : 32'h8120_0000;
  wire [31:0] pa = (is_priv || is_share) ? base + {4'h0, off} : la;
  wire        wr = |ls;
  wire        ex = m_excl[cur];
  wire        held = rsv_v[cur] && rsv_a[cur] == pa[31:2];

  wire        start = st == IDLE && cool == 2'd0 && any;
  wire        fwd = st == BUS && m_valid[own];
  wire        fin = fwd && (ready || fault);

  integer k;
  always @(posedge clk) begin
    if (!resetn) begin
      st    <= IDLE;
      own   <= 2'd0;
      last  <= 2'd3;
      cool  <= 2'd0;
      rsv_v <= 4'h0;
      go    <= 4'b0001;
    end else begin
      if (cool != 2'd0) cool <= cool - 2'd1;

      case (st)
        IDLE:
        if (start) begin
          own <= pick;
          st  <= over ? BAD : (ex && wr && !held) ? NAK : BUS;
        end
        BUS:
        if (fin || !m_valid[own]) begin
          st   <= IDLE;
          last <= own;
          cool <= 2'd3;
        end
        default: begin
          st   <= IDLE;
          last <= own;
          cool <= 2'd1;
        end
      endcase

      if (fin && ready) begin
        if (wr) begin
          for (k = 0; k < 4; k = k + 1) if (rsv_a[k] == pa[31:2]) rsv_v[k] <= 1'b0;
        end else if (ex) begin
          rsv_v[own] <= 1'b1;
          rsv_a[own] <= pa[31:2];
        end
      end
      if (st == NAK) rsv_v[own] <= 1'b0;

      for (k = 0; k < 4; k = k + 1) begin
        if (run[k] || k == 0) go[k] <= 1'b1;
        else if (!(st != IDLE && own == k)) go[k] <= 1'b0;
      end
    end
  end

  assign valid    = fwd;
  assign wstrb    = fwd ? ls : 4'h0;
  assign addr     = fwd ? {2'b00, pa} : 34'h0;
  assign wdata    = m_wdata[cur*32+:32];
  assign instr    = fwd && m_instr[own];
  assign owner    = cur;
  assign m_ready  = ((fwd && ready) || st == NAK) ? 4'b0001 << own : 4'b0000;
  assign m_fault  = ((fwd && fault) || st == BAD) ? 4'b0001 << own : 4'b0000;
  assign m_exokay = fwd && ready && ex;
endmodule
`default_nettype wire
