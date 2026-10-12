/* 发问的那一方，0 号结点的载荷：给 Hazard3 与 PicoRV32 两个回声各发八个数，回来的都要加了一、来路要对。
   一个镜像里三个结点各搬各的程序（目录里各指各的），这一段验的是这个。 */
#include <stdint.h>

#define REG(a) (*(volatile uint32_t *)(a))
#define LSR (*(volatile uint8_t *)0x10000005)
#define CTL 0x40040000u
#define RUN REG(CTL + 0x08)
#define TXDEST REG(CTL + 0x100)
#define TXDATA REG(CTL + 0x104)
#define RXSRC REG(CTL + 0x108)
#define RXDATA REG(CTL + 0x10c)
#define STAT REG(CTL + 0x110)

enum { RX = 1, ROOM = 2 };

void on_irq(void) {}

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

void main(void) {
  uint32_t bad = RUN != 0xd;
  say("noc echo\n");
  for (uint32_t to = 2; to < 4; to++)
    for (uint32_t i = 0; i < 8; i++) {
      uint32_t v = to << 16 | i * 0x101;
      while (!(STAT & ROOM)) {}
      TXDEST = to;
      TXDATA = v;
      while (!(STAT & RX)) {}
      bad += RXSRC != to;
      bad += RXDATA != v + 1;
    }
  say(bad ? "echo BAD " : "echo ok ");
  hex(bad);
  say("\ndone\n");
  for (;;) {}
}
