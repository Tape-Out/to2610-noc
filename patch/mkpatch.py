"""由 to2610-kvc 那棵源码树里的 soc.v 改出这一颗的 soc.v，并把差别存成 patch/noc.patch。
补丁是提交进仓的那一份，拼源码树时只套补丁；上游的 soc.v 变了、补丁套不上时，用这个脚本对着新的重出。
用法：mkpatch.py <拼好的源码树 build/src> > patch/noc.patch
"""
import difflib
import pathlib
import sys

src = pathlib.Path(sys.argv[1]) / "soc.v"
old = src.read_text(encoding="utf-8")
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


swap("  wire is_instruction, icache_flush;\n", """  wire is_instruction, icache_flush;
  wire [  3:0] t_valid, t_instr, t_excl, t_ready, t_fault, t_go, t_run, t_irq, t_ipi, t_soft, t_timer;
  wire [ 15:0] t_wstrb;
  wire [127:0] t_addr, t_wdata;
  wire         t_exokay;
  wire [  1:0] noc_owner;
  wire         noc_ready;
  wire [ 31:0] noc_rdata;
""")

swap("  wire is_flash = (cpu_mem_addr >= `SPI_NOR_MEM_ADDR_START && cpu_mem_addr < `SPI_NOR_MEM_ADDR_END);\n",
     "  wire is_flash = (cpu_mem_addr >= `SPI_NOR_MEM_ADDR_START && cpu_mem_addr < `SPI_NOR_MEM_ADDR_END);\n"
     "  wire is_noc = (cpu_mem_addr[31:12] == 20'h4_0040);\n")

# 每核一份 CLINT，照标准的排法摆在同一页里、四个核都看得见：msip 每核 4 字节一格，mtimecmp 每核 8 字节一格，
# mtime 共用。上游的 clint 只认 0 号核的那几个偏移，所以把各核自己那一格的地址换成它认的再递进去
cut("  clint_if #(\n      .BASE_HI(8'h02)\n  ) clint_if_I (", "  );\n", """  wire [  3:0] c_ready, c_vis;
  wire [127:0] c_rdata;
  wire [ 23:0] c_at = cpu_mem_addr[23:0];
  genvar ci;
  generate
    for (ci = 0; ci < 4; ci = ci + 1) begin : g_clint
      wire [23:0] c_own = c_at == 24'h00_0000 + 4 * ci ? 24'h00_0000 :
                          c_at == 24'h00_4000 + 8 * ci ? 24'h00_4000 :
                          c_at == 24'h00_4004 + 8 * ci ? 24'h00_4004 :
                          (ci == 0 && c_at[23:3] == 21'h00_17ff) ? c_at : 24'hff_fffc;
      clint_if #(
          .BASE_HI(8'h02)
      ) clint_if_I (
          .clk            (clk),
          .resetn         (resetn_soc),
          .bus_valid_i    (cpu_mem_valid),
          .bus_addr_i     ({cpu_mem_addr[31:24], c_own}),
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

swap("  wire non_instruction_invalid_access = !is_instruction && !(is_io || is_sdram || is_flash || is_reboot);\n",
     "  wire non_instruction_invalid_access = !is_instruction && !(is_io || is_sdram || is_flash || is_reboot || is_noc);\n")

cut("  kianv_harris_mc_edition #(\n      .RESET_ADDR      (`RESET_ADDR),", "      .PC             ()\n  );\n", """  noc_time time_I (
      .clk            (clk),
      .resetn         (resetn_soc),
      .sysclk_mhz_q8_8(sysclk_mhz_q8_8),
      .usec           (timer_counter)
  );
  assign icache_flush = 1'b0;

  genvar ti;
  generate
    for (ti = 0; ti < 4; ti = ti + 1) begin : g_tile
      noc_tile #(
          .HARTID(ti)
      ) tile_I (
          .clk      (clk),
          .resetn   (resetn_soc && t_go[ti]),
          .valid    (t_valid[ti]),
          .wstrb    (t_wstrb[ti*4+:4]),
          .addr     (t_addr[ti*32+:32]),
          .wdata    (t_wdata[ti*32+:32]),
          .instr    (t_instr[ti]),
          .excl     (t_excl[ti]),
          .ready    (t_ready[ti]),
          .fault    (t_fault[ti]),
          .exokay   (t_exokay),
          .rdata    (cpu_mem_rdata),
          .irq_box  (t_irq[ti]),
          .irq_ipi  (t_ipi[ti]),
          .irq_plic (ti == 0 ? irq_ctx0_w : 1'b0),
          .irq_soft (t_soft[ti]),
          .irq_timer(t_timer[ti])
      );
    end
  endgenerate

  noc_arb arb_I (
      .clk     (clk),
      .resetn  (resetn_soc),
      .m_valid (t_valid),
      .m_wstrb (t_wstrb),
      .m_addr  (t_addr),
      .m_wdata (t_wdata),
      .m_instr (t_instr),
      .m_excl  (t_excl),
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

d = difflib.unified_diff(old.splitlines(keepends=True), new.splitlines(keepends=True), "a/src/soc.v", "b/src/soc.v")
sys.stdout.writelines(d)
