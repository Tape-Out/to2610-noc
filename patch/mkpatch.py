"""由 to2610-kvc 那棵源码树改出这一颗的，并把差别存成 patch/noc.patch：soc.v（四个结点、仲裁、信箱，
各结点自己的 CLINT 与串口，两颗 KianV 各一份 PLIC）、chip_core.sv（多出三路串口的六根脚）、
KianV 的三个文件（引出原子指令的四根线）。
补丁是提交进仓的那一份，拼源码树时只套补丁；上游变了、补丁套不上时，用这个脚本对着新的重出。
用法：mkpatch.py <拼好的源码树 build/src> > patch/noc.patch
"""
import difflib
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
old = (root / "soc.v").read_text(encoding="utf-8")
new = old


def swap(a: str, b: str):
    global new
    assert new.count(a) == 1, (new.count(a), a[:60])
    new = new.replace(a, b)


def cut(head: str, tail: str, b: str):
    """把从 head 起到 tail 止（含）的一段换成 b。"""
    global new
    i = new.index(head)
    assert new.count(head) == 1, head[:60]
    j = new.index(tail, i) + len(tail)
    new = new[:i] + b + new[j:]


swap("    output wire uart_tx,\n    input wire uart_rx,\n",
     "    output wire uart_tx,\n    input wire uart_rx,\n    output wire [3:1] uart_txn,\n    input wire [3:1] uart_rxn,\n")

swap("  wire is_instruction, icache_flush;\n", """  wire is_instruction, icache_flush;
  wire [  3:0] t_valid, t_instr, t_excl, t_lock, t_ready, t_fault, t_go, t_run, t_irq, t_ipi, t_soft, t_timer;
  wire [ 15:0] t_wstrb;
  wire [127:0] t_addr, t_wdata;
  wire         t_exokay;
  wire [  1:0] noc_owner;
  wire         noc_ready;
  wire [ 31:0] noc_rdata;
  // 各结点私有的那段 SDRAM 与共享的那一段各多大：两份 Linux 各 24 MiB，另两个结点各 4 MiB，共享 8 MiB，合起来是片外那 64 MiB
  localparam [31:0] NOC_PRIV0 = 32'h0180_0000, NOC_PRIV1 = 32'h0180_0000, NOC_PRIV2 = 32'h0040_0000,
                    NOC_PRIV3 = 32'h0040_0000, NOC_SHARE = 32'h0080_0000;
  wire [ 31:0] noc_priv = noc_owner == 2'd0 ? NOC_PRIV0 : noc_owner == 2'd1 ? NOC_PRIV1 :
                          noc_owner == 2'd2 ? NOC_PRIV2 : NOC_PRIV3;
""")

# 内存大小寄存器各看各的：读到的是这个结点私有段的大小，引导程序据此把栈放在段顶
swap("    output wire cpu_freq_valid_o,\n    output wire mem_size_valid_o\n);\n",
     "    output wire cpu_freq_valid_o,\n    output wire mem_size_valid_o,\n    input  wire [31:0] mem_size_i\n);\n")
swap("                       mem_size_ready ? `SDRAM_SIZE :\n", "                       mem_size_ready ? mem_size_i :\n")
swap("  ) sysinfo_if_I (\n      .clk             (clk),\n",
     "  ) sysinfo_if_I (\n      .mem_size_i      (noc_priv),\n      .clk             (clk),\n")

swap("  wire is_flash = (cpu_mem_addr >= `SPI_NOR_MEM_ADDR_START && cpu_mem_addr < `SPI_NOR_MEM_ADDR_END);\n",
     "  wire is_flash = (cpu_mem_addr >= `SPI_NOR_MEM_ADDR_START && cpu_mem_addr < `SPI_NOR_MEM_ADDR_END);\n"
     "  wire is_noc = (cpu_mem_addr[31:12] == 20'h4_0040);\n")

# 每个结点一份 CLINT，同一个地址各看各的：每个结点都是自己那个世界里的 0 号 hart（KianV 的 mhartid 恒是 0），
# Linux 与 FreeRTOS 的移植都按 0 号 hart 找 msip 与 mtimecmp
cut("  clint_if #(\n      .BASE_HI(8'h02)\n  ) clint_if_I (", "  );\n", """  wire [  3:0] c_ready, c_vis;
  wire [127:0] c_rdata;
  genvar ci;
  generate
    for (ci = 0; ci < 4; ci = ci + 1) begin : g_clint
      clint_if #(
          .BASE_HI(8'h02)
      ) clint_if_I (
          .clk            (clk),
          .resetn         (resetn_soc),
          .bus_valid_i    (cpu_mem_valid && noc_owner == ci),
          .bus_addr_i     (cpu_mem_addr),
          .bus_wstrb_i    (cpu_mem_wstrb),
          .bus_wdata_i    (cpu_mem_wdata),
          .bus_rdata_o    (c_rdata[ci*32+:32]),
          .bus_ready_o    (c_ready[ci]),
          .is_valid_o     (c_vis[ci]),
          .timer_counter_i(mtime_for_system),
          .IRQ3           (t_soft[ci]),
          .IRQ7           (t_timer[ci])
      );
    end
  endgenerate
  assign clint_ready = |c_ready;
  assign clint_valid_vis = |c_vis;
  assign clint_rdata = c_ready[1] ? c_rdata[63:32] : c_ready[2] ? c_rdata[95:64] : c_ready[3] ? c_rdata[127:96] : c_rdata[31:0];
  assign IRQ3 = t_soft[0];
  assign IRQ7 = t_timer[0];
""")

# PicoRV32 的访存口只出按字对齐的地址，读线路状态时来的是它所在的那个字。这个字里另外三个字节上游本来就读成 0，
# 整个字的读都认成线路状态，按字节读的核看不出差别。只认读：这个字里还有 16550 的 MCR、MSR、SCR，
# OpenSBI 与 Linux 的驱动会去写，串口不应答写，得留给「没人认领」的那一路去应答
swap("  wire match_lsr = bus_valid_i && (bus_addr_i == LSR_ADDR) && rd;\n",
     "  wire match_lsr = bus_valid_i && ({bus_addr_i[31:2], LSR_ADDR[1:0]} == LSR_ADDR) && rd;\n")
swap("  wire match_lsr = (cpu_mem_addr == `UART_LSR_ADDR0);\n",
     "  wire match_lsr = ({cpu_mem_addr[31:2], 2'b01} == `UART_LSR_ADDR0) && !wr;\n")
# 发字只认最低那个字节的写：PicoRV32 往 1 至 3 号偏移写一个字节，到片上是同一个字、别的字节的写选通，不该发出去
swap("  wire match_tx = bus_valid_i && (bus_addr_i == TX_ADDR) && wr;\n",
     "  wire match_tx = bus_valid_i && (bus_addr_i == TX_ADDR) && bus_wstrb_i[0];\n")
swap("  wire match_tx = (cpu_mem_addr == `UART_TX_ADDR0);\n  wire match_rx = (cpu_mem_addr == `UART_RX_ADDR0);\n",
     "  wire match_tx = (cpu_mem_addr == `UART_TX_ADDR0) && cpu_mem_wstrb[0];\n"
     "  wire match_rx = (cpu_mem_addr == `UART_RX_ADDR0) && !wr;\n")

# 每个结点一路串口，同一个地址各看各的；波特率的分频四路共用上游那一个寄存器
cut("  uart_if #(\n      .LSR_ADDR(`UART_LSR_ADDR0),", "      .lsr_ready_o(uart_lsr_rdy)\n  );\n", """  wire [  3:0] u_ready, u_busy, u_txrdy, u_lsrrdy, u_irq, u_tx;
  wire [127:0] u_rdata, u_rx;
  wire [  3:0] u_rxpin = {uart_rxn, uart_rx};
  genvar ui;
  generate
    for (ui = 0; ui < 4; ui = ui + 1) begin : g_uart
      uart_if #(
          .LSR_ADDR(`UART_LSR_ADDR0),
          .TX_ADDR (`UART_TX_ADDR0),
          .RX_ADDR (`UART_RX_ADDR0),
          .HAS_TEMT(1'b1),
          .HAS_THRE(1'b1)
      ) uart_if_I (
          .clk        (clk),
          .resetn     (resetn_soc),
          .bus_valid_i(cpu_mem_valid && noc_owner == ui),
          .bus_addr_i (cpu_mem_addr),
          .bus_wstrb_i(cpu_mem_wstrb),
          .bus_wdata_i(cpu_mem_wdata),
          .bus_rdata_o(u_rdata[ui*32+:32]),
          .bus_ready_o(u_ready[ui]),
          .div_i      (div_reg_bus0[15:0]),
          .uart_tx    (u_tx[ui]),
          .uart_rx    (u_rxpin[ui]),
          .rx_data_o  (u_rx[ui*32+:32]),
          .tx_busy_o  (u_busy[ui]),
          .tx_ready_o (u_txrdy[ui]),
          .lsr_ready_o(u_lsrrdy[ui])
      );
      assign u_irq[ui] = ~(&u_rx[ui*32+:32]) || u_busy[ui];
    end
  endgenerate
  assign uart_tx          = u_tx[0];
  assign uart_txn         = u_tx[3:1];
  assign uart_if_ready    = |u_ready;
  assign uart_if_rdata    = u_rdata[noc_owner*32+:32];
  assign uart_rx_data_obs = u_rx[31:0];
  assign uart_tx_busy_obs = u_busy[0];
  assign uart_tx_rdy      = u_txrdy[0];
  assign uart_lsr_rdy     = u_lsrrdy[0];
""")

# 两颗 KianV 各一份 PLIC：源 10 是自己的串口（上游原样），11 是信箱来包，12 是核间中断
cut("  wire uart_irq = ~(&uart_rx_data_obs) || uart_tx_busy_obs;\n", "      .irq_ctx1_o       (irq_ctx1_w)\n  );\n", """  wire [ 1:0] p_ready, p_vis, k_ctx0, k_ctx1;
  wire [63:0] p_rdata;
  genvar pi;
  generate
    for (pi = 0; pi < 2; pi = pi + 1) begin : g_plic
      plic_if #(
          .BASE_HI(8'h0C)
      ) plic_if_I (
          .clk              (clk),
          .resetn           (resetn_soc),
          .bus_valid_i      (cpu_mem_valid && noc_owner == pi),
          .bus_addr_i       (cpu_mem_addr),
          .bus_wstrb_i      (cpu_mem_wstrb),
          .bus_wdata_i      (cpu_mem_wdata),
          .bus_rdata_o      (p_rdata[pi*32+:32]),
          .bus_ready_o      (p_ready[pi]),
          .is_valid_o       (p_vis[pi]),
          .interrupt_request({19'b0, t_ipi[pi], t_irq[pi], u_irq[pi], 9'b0}),
          .irq_ctx0_o       (k_ctx0[pi]),
          .irq_ctx1_o       (k_ctx1[pi])
      );
    end
  endgenerate
  assign plic_ready     = |p_ready;
  assign plic_valid_vis = |p_vis;
  assign plic_rdata     = p_ready[1] ? p_rdata[63:32] : p_rdata[31:0];
  assign irq_ctx0_w     = k_ctx0[0];
  assign irq_ctx1_w     = k_ctx1[0];
""")

# SD 卡口、SPI 网卡口、GPIO 只归 0 号结点；别的结点访问这几处没人认领，读到 0
swap("  wire spi_mem_valid0 = cpu_mem_valid && hit_spi0;\n  wire spi_mem_valid1 = cpu_mem_valid && hit_spi1;\n"
     "  wire gpio_valid = cpu_mem_valid && hit_gpio;\n",
     "  wire spi_mem_valid0 = cpu_mem_valid && hit_spi0 && noc_owner == 2'd0;\n"
     "  wire spi_mem_valid1 = cpu_mem_valid && hit_spi1 && noc_owner == 2'd0;\n"
     "  wire gpio_valid = cpu_mem_valid && hit_gpio && noc_owner == 2'd0;\n")

swap("  wire non_instruction_invalid_access = !is_instruction && !(is_io || is_sdram || is_flash || is_reboot);\n",
     "  wire non_instruction_invalid_access = !is_instruction && !(is_io || is_sdram || is_flash || is_reboot || is_noc);\n")

cut("  kianv_harris_mc_edition #(\n      .RESET_ADDR      (`RESET_ADDR),", "      .PC             ()\n  );\n", """  noc_time time_I (
      .clk            (clk),
      .resetn         (resetn_soc),
      .sysclk_mhz_q8_8(sysclk_mhz_q8_8),
      .usec           (timer_counter)
  );

  // 0、1 号结点：KianV。访存口与结点口同形，直接接仲裁；微秒计数由 noc_time 出，核自己的那一路不接。
  // 原子指令在总线这一处裁决：AMO 的读与写之间锁着不换人；LR 是独占读，SC 是独占写，预留不在时仲裁不让它上总线
  wire [ 1:0] k_lr, k_sc, k_flush;
  wire [67:0] k_addr;
  genvar ki;
  generate
    for (ki = 0; ki < 2; ki = ki + 1) begin : g_kv
      kianv_harris_mc_edition #(
          .RESET_ADDR      (`RESET_ADDR),
          .NUM_ENTRIES_ITLB(`NUM_ENTRIES_ITLB),
          .NUM_ENTRIES_DTLB(`NUM_ENTRIES_DTLB)
      ) kianv_I (
          .clk            (clk),
          .resetn         (resetn_soc && t_go[ki]),
          .sysclk_mhz_q8_8(sysclk_mhz_q8_8),
          .mem_ready      (t_ready[ki]),
          .mem_valid      (t_valid[ki]),
          .mem_wstrb      (t_wstrb[ki*4+:4]),
          .mem_addr       (k_addr[ki*34+:34]),
          .mem_wdata      (t_wdata[ki*32+:32]),
          .mem_rdata      (cpu_mem_rdata),
          .access_fault   (t_fault[ki]),
          .timer_counter  (),
          .is_instruction (t_instr[ki]),
          .icache_flush   (k_flush[ki]),
          .IRQ3           (t_soft[ki]),
          .IRQ7           (t_timer[ki]),
          .IRQ9           (k_ctx1[ki]),
          .IRQ11          (k_ctx0[ki]),
          .PC             (),
          .amo_lock       (t_lock[ki]),
          .lr_read        (k_lr[ki]),
          .sc_write       (k_sc[ki]),
          .sc_abort       (!t_exokay)
      );
      assign t_addr[ki*32+:32] = k_addr[ki*34+:32];
      assign t_excl[ki]        = k_lr[ki] || k_sc[ki];
    end
  endgenerate
  assign icache_flush = |k_flush;
  assign t_lock[3:2]  = 2'b00;

  // 2 号结点：Hazard3。外部中断线 0 是信箱来包，1 是核间中断，2 是自己的串口
  noc_tile tile_I (
      .clk      (clk),
      .resetn   (resetn_soc && t_go[2]),
      .valid    (t_valid[2]),
      .wstrb    (t_wstrb[11:8]),
      .addr     (t_addr[95:64]),
      .wdata    (t_wdata[95:64]),
      .instr    (t_instr[2]),
      .excl     (t_excl[2]),
      .ready    (t_ready[2]),
      .fault    (t_fault[2]),
      .exokay   (t_exokay),
      .rdata    (cpu_mem_rdata),
      .irq_box  (t_irq[2]),
      .irq_ipi  (t_ipi[2]),
      .irq_plic (u_irq[2]),
      .irq_soft (t_soft[2]),
      .irq_timer(t_timer[2])
  );

  // 3 号结点：PicoRV32，从 Flash 的另一处起步（它的指令集与另三颗不同，程序另编）
  noc_pico pico_I (
      .clk      (clk),
      .resetn   (resetn_soc && t_go[3]),
      .valid    (t_valid[3]),
      .wstrb    (t_wstrb[15:12]),
      .addr     (t_addr[127:96]),
      .wdata    (t_wdata[127:96]),
      .instr    (t_instr[3]),
      .excl     (t_excl[3]),
      .ready    (t_ready[3]),
      .fault    (t_fault[3]),
      .exokay   (t_exokay),
      .rdata    (cpu_mem_rdata),
      .irq_timer(t_timer[3]),
      .irq_soft (t_soft[3]),
      .irq_ipi  (t_ipi[3]),
      .irq_box  (t_irq[3]),
      .irq_uart (u_irq[3])
  );

  noc_arb #(
      .PRIV0(NOC_PRIV0),
      .PRIV1(NOC_PRIV1),
      .PRIV2(NOC_PRIV2),
      .PRIV3(NOC_PRIV3),
      .SHARE(NOC_SHARE)
  ) arb_I (
      .clk     (clk),
      .resetn  (resetn_soc),
      .m_valid (t_valid),
      .m_wstrb (t_wstrb),
      .m_addr  (t_addr),
      .m_wdata (t_wdata),
      .m_instr (t_instr),
      .m_excl  (t_excl),
      .m_lock  (t_lock),
      .m_ready (t_ready),
      .m_fault (t_fault),
      .m_exokay(t_exokay),
      .run     (t_run),
      .go      (t_go),
      .valid   (cpu_mem_valid),
      .wstrb   (cpu_mem_wstrb),
      .addr    (cpu_mem_addr_phy),
      .wdata   (cpu_mem_wdata),
      .instr   (is_instruction),
      .owner   (noc_owner),
      .ready   (cpu_mem_ready),
      .fault   (access_fault_ready)
  );

  mkNocBox box_I (
      .CLK        (clk),
      .RST_N      (resetn_soc),
      .bus_valid_i(cpu_mem_valid && is_noc),
      .bus_owner_i(noc_owner),
      .bus_addr_i (cpu_mem_addr[8:0]),
      .bus_write_i(|cpu_mem_wstrb),
      .bus_wdata_i(cpu_mem_wdata),
      .bus_rdata_o(noc_rdata),
      .bus_ready_o(noc_ready),
      .run        (t_run),
      .irq        (t_irq),
      .ipi        (t_ipi)
  );
""")

swap("      (hit_gpio && gpio_ready) ||\n      (is_io    && io_ready) ||\n",
     "      (hit_gpio && gpio_ready) ||\n      (is_noc   && noc_ready) ||\n      (is_io    && io_ready) ||\n")
swap("      (hit_gpio && gpio_ready)      ? gpio_rdata      :\n",
     "      (hit_gpio && gpio_ready)      ? gpio_rdata      :\n      (is_noc   && noc_ready)       ? noc_rdata       :\n")

# 片外的 SDRAM 换成同封装 64 MiB 的（MT48LC32M16A2，列地址 10 位）：两份 Linux 各要 24 MiB
swap("      .addr     (cache_addr_o[24:0]),\n", "      .addr     (cache_addr_o[25:0]),\n")

out = list(difflib.unified_diff(old.splitlines(keepends=True), new.splitlines(keepends=True), "a/src/soc.v", "b/src/soc.v"))

# KianV 引出原子指令的四根线，给仲裁裁决用（做法同 to2610-smp）：AMO 从读到写这一段、LR 的读、SC 的写各一根出去，
# SC 写没写成由外面说了算。核里原有的预留照旧，只决定试不试
HOOKS = "    output wire amo_lock,\n    output wire lr_read,\n    output wire sc_write,\n    input  wire sc_abort\n);\n"
PASS = "      .amo_lock (amo_lock),\n      .lr_read  (lr_read),\n      .sc_write (sc_write),\n      .sc_abort (sc_abort),\n"
# 三路串口的六根脚排在上游那 54 根的后面：54、56、58 是 1 至 3 号结点的 RX，55、57、59 是 TX
PADS = [
    ("    parameter NUM_BIDIR_PADS = 54  // unified bidirectional pads (53 used, 1 spare)\n",
     "    parameter NUM_BIDIR_PADS = 60  // upstream's 54, then RX and TX of the UARTs of nodes 1 to 3\n"),
    ("    assign bidir_out[UART_RX_IDX]    = 1'b0;\n",
     "    assign bidir_out[UART_RX_IDX]    = 1'b0;\n    assign bidir_out[54] = 1'b0;\n    assign bidir_out[56] = 1'b0;\n    assign bidir_out[58] = 1'b0;\n"),
    ("        .uart_rx (bidir_in [UART_RX_IDX]),\n",
     "        .uart_rx (bidir_in [UART_RX_IDX]),\n        .uart_txn({bidir_out[59], bidir_out[57], bidir_out[55]}),\n"
     "        .uart_rxn({bidir_in[58], bidir_in[56], bidir_in[54]}),\n"),
    ("        bidir_oe_i[UART_TX_IDX]    = 1'b1;\n",
     "        bidir_oe_i[UART_TX_IDX]    = 1'b1;\n        bidir_oe_i[55] = 1'b1;\n        bidir_oe_i[57] = 1'b1;\n        bidir_oe_i[59] = 1'b1;\n"),
]
MORE = {
    "chip_core.sv": PADS,
    "defines_soc.vh": [("`define SDRAM_SIZE (1024*1024*32)\n", "`define SDRAM_SIZE (1024*1024*64)\n")],
    # 上游的控制器给列地址的是 {addr[10:2], 0}，A9 已经带着 addr[10]，只是 9 位列的片子不看它、行里又用了一遍；
    # 10 位列的片子上 A9 是真的列地址，行改从 addr[11] 取，顶上多一位
    "sdram/mt48lc16m16a2_ctrl.v": [
        ("    input  wire [24:0] addr,\n", "    input  wire [25:0] addr,\n"),
        ("  wire [12:0] cur_row_w = {addr[24:23], addr[20:10]};\n", "  wire [12:0] cur_row_w = {addr[25:23], addr[20:11]};\n"),
        ('    $display("row  = {addr[24:23], addr[20:10]}");\n', '    $display("row  = {addr[25:23], addr[20:11]}");\n'),
    ],
    "kianv_harris_edition/control_unit.v": [
        ("    output wire div_valid,\n    input  wire div_ready\n);\n", "    output wire div_valid,\n    input  wire div_ready,\n\n" + HOOKS),
        ("      .mem_valid(fsm_mem_valid),\n      .mem_ready(mem_ready),\n", "      .mem_valid(fsm_mem_valid),\n      .mem_ready(mem_ready),\n" + PASS),
    ],
    "kianv_harris_edition/kianv_harris_mc_edition.v": [
        ("    output wire        is_instruction,\n    output wire        icache_flush\n);\n",
         "    output wire        is_instruction,\n    output wire        icache_flush,\n" + HOOKS),
        ("      .icache_flush     (icache_flush),\n", "      .icache_flush     (icache_flush),\n" + PASS),
    ],
    "kianv_harris_edition/main_fsm.v": [
        ("    input wire stall,\n    input wire mem_ready\n);\n", "    input wire stall,\n    input wire mem_ready,\n" + HOOKS),
        ("          mem_ready:          state_nxt = AMO_SC_SUCCESS;\n", "          mem_ready:          state_nxt = sc_abort ? AMO_SC_FAIL : AMO_SC_SUCCESS;\n"),
        ("    incr_inst_retired = retire_pulse_int_final;\n  end\n\nendmodule\n",
         "    incr_inst_retired = retire_pulse_int_final;\n  end\n\n"
         "  assign amo_lock = state == AMO_OP_READ || state == AMO_OP_WB || state == AMO_OP_EXEC ||\n"
         "                    state == AMO_OP_ADDR || state == AMO_OP_WRITE;\n"
         "  assign lr_read  = state == AMO_LR_READ;\n"
         "  assign sc_write = state == AMO_SC_WRITE;\n\nendmodule\n"),
    ],
}
for name, pairs in MORE.items():
    a = b = (root / name).read_text(encoding="utf-8")
    for x, y in pairs:
        assert b.count(x) == 1, (name, b.count(x), x[:50])
        b = b.replace(x, y)
    out += difflib.unified_diff(a.splitlines(keepends=True), b.splitlines(keepends=True), "a/src/" + name, "b/src/" + name)
sys.stdout.writelines(out)
