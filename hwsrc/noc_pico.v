// 一个结点：PicoRV32（上游是 RV32IMC），可选的扩展与提速选项全开，协处理器口 PCPI 上挂两样：
//
//   签名指令  custom-1（操作码 0101011，funct3 与 funct7 都是 0）：rs1 为 0 时 rd 得 0x656B6568，
//             为 1 时得 0x38323231，其余得 0。两个字按小端存进内存就是 "heke1228"。
//             custom-0 被 PicoRV32 自己的中断指令占着，所以用 custom-1；标准程序用不到这个操作码，
//             它的别的编码照旧按非法指令陷入
//   A 扩展    Zalrsc 与 Zaamo（操作码 0101111，funct3 010）。PCPI 不带访存口，协处理器自己带一个，
//             与核的访存口二选一出去：核等协处理器时自己的访存口空着（它预取的下一条取完才动）。
//             lr.w 是独占读；sc.w 是独占写，预留不在时仲裁不让它上总线，回 1；
//             九条 AMO 是独占读、算、独占写，仲裁说没写成（别的核在中间写了这个字）就从读重来。
//             地址没对齐时不应答，核按非法指令陷入
//   fence.i   空操作：没有指令缓存。上游不认这条指令，会当成非法指令
//
// 访存口对外与别的结点同形，接四路仲裁。PicoRV32 没有访问出错的口：仲裁判出错时这一次访问照常收尾，
// 另起它的 2 号中断（总线错）。中断是它自带的那一套：0 自带计时器、1 非法指令、2 总线错是它固定的，
// 3 是这个结点 CLINT 的计时器，4 软件中断，5 核间中断，6 信箱来包，7 自己的串口；3 至 7 是电平，不锁存
`default_nettype none
module noc_pico #(
    parameter [31:0] RESET_ADDR = 32'h2018_0000,
    parameter [31:0] IRQ_ADDR   = 32'h2018_0010
) (
    input  wire        clk,
    input  wire        resetn,

    output wire        valid,
    output wire [ 3:0] wstrb,
    output wire [31:0] addr,
    output wire [31:0] wdata,
    output wire        instr,
    output wire        excl,
    input  wire        ready,
    input  wire        fault,
    input  wire        exokay,
    input  wire [31:0] rdata,

    input  wire        irq_timer,
    input  wire        irq_soft,
    input  wire        irq_ipi,
    input  wire        irq_box,
    input  wire        irq_uart
);
  wire        m_valid, m_instr;
  wire [31:0] m_addr, m_wdata;
  wire [ 3:0] m_wstrb;
  wire        p_valid;
  wire [31:0] p_insn, p_rs1, p_rs2;
  reg         bus_err;

  // fence.i：这颗核没有指令缓存，当拍应答、什么也不做（上游只认 fence，不认 fence.i）
  wire fencei = p_valid && p_insn[6:0] == 7'b0001111 && p_insn[14:12] == 3'b001;

  // 签名指令：组合出结果，当拍应答
  wire sig = p_valid && p_insn[6:0] == 7'b0101011 && p_insn[14:12] == 3'b000 && p_insn[31:25] == 7'b0000000;
  wire [31:0] sig_rd = p_rs1 == 32'd0 ? 32'h656B_6568 : p_rs1 == 32'd1 ? 32'h3832_3231 : 32'h0;

  // A 扩展
  wire [4:0] f5 = p_insn[31:27];
  wire is_lr = f5 == 5'b00010 && p_insn[24:20] == 5'd0;
  wire is_sc = f5 == 5'b00011;
  wire is_amo = f5 == 5'b00001 || f5 == 5'b00000 || f5 == 5'b00100 || f5 == 5'b01100 || f5 == 5'b01000 ||
                f5 == 5'b10000 || f5 == 5'b10100 || f5 == 5'b11000 || f5 == 5'b11100;
  wire atom = p_valid && p_insn[6:0] == 7'b0101111 && p_insn[14:12] == 3'b010 && (is_lr || is_sc || is_amo) &&
              p_rs1[1:0] == 2'b00;

  localparam [2:0] IDLE = 3'd0, RD = 3'd1, GAP = 3'd2, WR = 3'd3, DONE = 3'd4;
  reg [ 2:0] st;
  reg [31:0] old, res;

  reg [31:0] calc;
  always @(*) begin
    case (f5)
      5'b00001: calc = p_rs2;
      5'b00000: calc = old + p_rs2;
      5'b00100: calc = old ^ p_rs2;
      5'b01100: calc = old & p_rs2;
      5'b01000: calc = old | p_rs2;
      5'b10000: calc = $signed(old) < $signed(p_rs2) ? old : p_rs2;
      5'b10100: calc = $signed(old) > $signed(p_rs2) ? old : p_rs2;
      5'b11000: calc = old < p_rs2 ? old : p_rs2;
      default:  calc = old > p_rs2 ? old : p_rs2;
    endcase
  end

  wire a_bus = st == RD || st == WR;
  always @(posedge clk) begin
    if (!resetn) st <= IDLE;
    else begin
      case (st)
        // 核的访存口空了才动：它预取的下一条指令可能还在路上
        IDLE: if (atom && !m_valid) st <= is_sc ? WR : RD;
        RD:
        if (ready) begin
          old <= rdata;
          res <= rdata;
          st  <= (is_lr || fault) ? DONE : GAP;
        end
        GAP: st <= WR;
        WR:
        if (ready) begin
          if (is_sc) begin
            res <= {31'h0, !exokay};
            st  <= DONE;
          // 没写成：回 IDLE 空一拍，再从读重来
          end else st <= (exokay || fault) ? DONE : IDLE;
        end
        default: st <= IDLE;
      endcase
    end
  end

  // 应答的下一拍核就把 p_valid 放下，状态机回到 IDLE 时不会把同一条指令再做一遍
  wire a_done = st == DONE;

  assign valid = a_bus ? 1'b1 : m_valid;
  assign wstrb = a_bus ? (st == WR ? 4'hf : 4'h0) : m_wstrb;
  assign addr  = a_bus ? p_rs1 : m_addr;
  assign wdata = a_bus ? (is_sc ? p_rs2 : calc) : m_wdata;
  assign instr = !a_bus && m_instr;
  assign excl  = a_bus;

  always @(posedge clk) begin
    if (!resetn) bus_err <= 1'b0;
    else bus_err <= valid && fault;
  end

  picorv32 #(
      .ENABLE_COUNTERS     (1),
      .ENABLE_COUNTERS64   (1),
      .ENABLE_REGS_16_31   (1),
      .ENABLE_REGS_DUALPORT(1),
      .BARREL_SHIFTER      (1),
      .TWO_CYCLE_COMPARE   (0),
      .TWO_CYCLE_ALU       (0),
      .COMPRESSED_ISA      (1),
      .CATCH_MISALIGN      (1),
      .CATCH_ILLINSN       (1),
      .ENABLE_PCPI         (1),
      .ENABLE_MUL          (1),
      .ENABLE_FAST_MUL     (1),
      .ENABLE_DIV          (1),
      .ENABLE_IRQ          (1),
      .ENABLE_IRQ_QREGS    (1),
      .ENABLE_IRQ_TIMER    (1),
      .ENABLE_TRACE        (0),
      .LATCHED_IRQ         (32'h0000_0007),
      .PROGADDR_RESET      (RESET_ADDR),
      .PROGADDR_IRQ        (IRQ_ADDR)
  ) cpu_I (
      .clk         (clk),
      .resetn      (resetn),
      .trap        (),
      .mem_valid   (m_valid),
      .mem_instr   (m_instr),
      .mem_ready   (ready && !a_bus),
      .mem_addr    (m_addr),
      .mem_wdata   (m_wdata),
      .mem_wstrb   (m_wstrb),
      .mem_rdata   (rdata),
      .mem_la_read (),
      .mem_la_write(),
      .mem_la_addr (),
      .mem_la_wdata(),
      .mem_la_wstrb(),
      .pcpi_valid  (p_valid),
      .pcpi_insn   (p_insn),
      .pcpi_rs1    (p_rs1),
      .pcpi_rs2    (p_rs2),
      .pcpi_wr     (sig || a_done),
      .pcpi_rd     (sig ? sig_rd : is_amo ? old : res),
      .pcpi_wait   (atom && !a_done),
      .pcpi_ready  (sig || fencei || a_done),
      .irq         ({24'h0, irq_uart, irq_box, irq_ipi, irq_soft, irq_timer, bus_err, 2'b00}),
      .eoi         (),
      .trace_valid (),
      .trace_data  ()
  );
endmodule
`default_nettype wire
