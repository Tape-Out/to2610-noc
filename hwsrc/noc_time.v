// 微秒计数：四个核的 CLINT 共用的 mtime 的来源。to2610-kvc 里这个数是 KianV 核自己数出来再引出来的，
// 这一颗没有 KianV 核，照它的办法另数一份：主频以 8.8 定点的兆赫给，每拍累加 1.0，够一个主频就进一微秒。
`default_nettype none
module noc_time (
    input  wire        clk,
    input  wire        resetn,
    input  wire [15:0] sysclk_mhz_q8_8,
    output reg  [63:0] usec
);
  wire [16:0] mhz = {1'b0, sysclk_mhz_q8_8 < 16'h0100 ? 16'h0100 : sysclk_mhz_q8_8};
  reg  [16:0] acc;
  wire [16:0] nxt = acc + 17'h0_0100;

  always @(posedge clk) begin
    if (!resetn) begin
      acc  <= 17'h0;
      usec <= 64'h0;
    end else if (nxt >= mhz) begin
      acc  <= nxt - mhz;
      usec <= usec + 64'h1;
    end else acc <= nxt;
  end
endmodule
`default_nettype wire
