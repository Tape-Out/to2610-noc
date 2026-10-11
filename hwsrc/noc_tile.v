// 网格上的一个结点：一颗 Hazard3，把它的单口 AHB5 转成 KianV 片上总线的那种 valid/ready。
//
// AHB 的地址拍与数据拍是错开的：这一次的数据拍里核已经把下一次的地址摆出来了。桥在 hready 为高的那一拍
// 收下地址，随后把 hready 压低，到片上总线应答的那一拍再放开，读数据与独占访问的结果同一拍交回去。
//
// 片上几个外设的应答在请求撤掉之后还要高一拍，所以一次访问做完到下一次举手之间空两拍。
// 访问出错照 AHB 的两拍错误应答回给核，核进访存异常。
`default_nettype none
module noc_tile #(
    parameter [31:0] HARTID = 32'h0
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

    input  wire        irq_box,
    input  wire        irq_ipi,
    input  wire        irq_plic,
    input  wire        irq_soft,
    input  wire        irq_timer
);
  localparam [2:0] IDLE = 3'd0, GAP = 3'd1, REQ = 3'd2, ERR1 = 3'd3, ERR2 = 3'd4;

  wire [31:0] haddr, hwdata;
  wire        hwrite, hexcl, pwrup;
  wire [ 1:0] htrans;
  wire [ 2:0] hsize;
  wire [ 3:0] hprot;

  reg  [ 2:0] st;
  reg  [ 1:0] cool;
  reg  [31:0] a;
  reg  [ 1:0] sz;
  reg         w, ex, op;

  wire        hready = st == IDLE || (st == REQ && ready) || st == ERR2;
  wire        hresp = st == ERR1 || st == ERR2;
  wire        take = hready && htrans[1];

  always @(posedge clk) begin
    if (!resetn) begin
      st   <= IDLE;
      cool <= 2'd0;
      a    <= 32'h0;
      sz   <= 2'd0;
      w    <= 1'b0;
      ex   <= 1'b0;
      op   <= 1'b0;
    end else begin
      if (st == REQ && (ready || fault)) cool <= 2'd2;
      else if (cool != 2'd0) cool <= cool - 2'd1;

      if (take) begin
        a  <= haddr;
        sz <= hsize[1:0];
        w  <= hwrite;
        ex <= hexcl;
        op <= !hprot[0];
      end

      case (st)
        IDLE: if (take) st <= cool == 2'd0 ? REQ : GAP;
        GAP: if (cool == 2'd0) st <= REQ;
        REQ:
        if (fault) st <= ERR1;
        else if (ready) st <= take ? GAP : IDLE;
        ERR1: st <= ERR2;
        ERR2: st <= take ? GAP : IDLE;
        default: st <= IDLE;
      endcase
    end
  end

  wire [3:0] lanes = sz == 2'd0 ? 4'b0001 << a[1:0] : sz == 2'd1 ? 4'b0011 << a[1:0] : 4'b1111;

  assign valid = st == REQ;
  assign addr  = a;
  assign wstrb = w ? lanes : 4'b0000;
  assign wdata = hwdata;
  assign instr = op;
  assign excl  = ex;

  hazard3_cpu_1port #(
      .RESET_VECTOR      (32'h2010_0000),
      .MTVEC_INIT        (32'h2010_0000),
      .EXTENSION_A       (1),
      .EXTENSION_C       (1),
      .EXTENSION_M       (1),
      // 上游的 ALU 只在开了 Zbb 时把 MAXU、MINU 当无符号比，不开的话 amomaxu、amominu 按有符号算
      .EXTENSION_ZBB     (1),
      .EXTENSION_ZIFENCEI(1),
      .CSR_M_MANDATORY   (1),
      .CSR_M_TRAP        (1),
      .CSR_COUNTER       (1),
      .DEBUG_SUPPORT     (0),
      .NUM_IRQS          (3),
      .MULDIV_UNROLL     (1),
      .MUL_FAST          (0)
  ) cpu (
      .clk                       (clk),
      .clk_always_on             (clk),
      .rst_n                     (resetn),
      .pwrup_req                 (pwrup),
      .pwrup_ack                 (pwrup),
      .clk_en                    (),
      .unblock_out               (),
      .unblock_in                (1'b0),
      .haddr                     (haddr),
      .hwrite                    (hwrite),
      .htrans                    (htrans),
      .hsize                     (hsize),
      .hburst                    (),
      .hprot                     (hprot),
      .hmastlock                 (),
      .hmaster                   (),
      .hexcl                     (hexcl),
      .hready                    (hready),
      .hresp                     (hresp),
      .hexokay                   (st == REQ && ready && exokay),
      .hwdata                    (hwdata),
      .hrdata                    (rdata),
      .fence_i_vld               (),
      .fence_d_vld               (),
      .fence_rdy                 (1'b1),
      .dbg_req_halt              (1'b0),
      .dbg_req_halt_on_reset     (1'b0),
      .dbg_req_resume            (1'b0),
      .dbg_halted                (),
      .dbg_running               (),
      .dbg_data0_rdata           (32'h0),
      .dbg_data0_wdata           (),
      .dbg_data0_wen             (),
      .dbg_instr_data            (32'h0),
      .dbg_instr_data_vld        (1'b0),
      .dbg_instr_data_rdy        (),
      .dbg_instr_caught_exception(),
      .dbg_instr_caught_ebreak   (),
      .dbg_sbus_addr             (32'h0),
      .dbg_sbus_write            (1'b0),
      .dbg_sbus_size             (2'b00),
      .dbg_sbus_vld              (1'b0),
      .dbg_sbus_rdy              (),
      .dbg_sbus_err              (),
      .dbg_sbus_wdata            (32'h0),
      .dbg_sbus_rdata            (),
      .mhartid_val               (HARTID),
      .eco_version               (4'h0),
      .irq                       ({irq_plic, irq_ipi, irq_box}),
      .soft_irq                  (irq_soft),
      .timer_irq                 (irq_timer)
  );
endmodule
`default_nettype wire
