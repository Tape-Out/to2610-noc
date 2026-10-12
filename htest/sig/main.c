/* 0 号核：放开 PicoRV32 那个结点，把它用签名指令读到的两个字当字符串打出来，再打它自己核对的结论 */
#include <stdint.h>

#define REG(a) (*(volatile uint32_t *)(a))
#define LSR (*(volatile uint8_t *)0x10000005)
#define CTL 0x40040000u
#define RUN REG(CTL + 0x08)
#define RXDATA REG(CTL + 0x10c)
#define STAT REG(CTL + 0x110)

static void putch(char c) {
  while (!(LSR & 0x60)) {}
  REG(0x10000000) = c;
}

static void say(const char *s) {
  while (*s) putch(*s++);
}

static void hex(uint32_t v) {
  for (int i = 28; i >= 0; i -= 4) putch("0123456789abcdef"[v >> i & 15]);
}

static uint32_t hear(void) {
  while (!(STAT & 1)) {}
  return RXDATA;
}

void main(void) {
  /* 分频寄存器复位后是 1。主频寄存器是 8.8 定点的兆赫，乘 15625/4 得赫兹 */
  uint32_t hz = (REG(0x10000014) & 0xffff) * 15625 / 4;
  REG(0x1000000c) = hz / 115200;
  say("noc sig\n");
  RUN = 0x9;
  for (int k = 0; k < 2; k++) {
    uint32_t w = hear();
    for (int i = 0; i < 32; i += 8) putch(w >> i);
  }
  putch('\n');
  uint32_t bad = hear();
  say(bad ? "sig BAD " : "sig ok ");
  hex(bad);
  say("\ndone\n");
  for (;;) {}
}
