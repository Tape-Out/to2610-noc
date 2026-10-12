/* 每个结点一路串口，同一个地址各看各的。四个结点各在自己的串口上报一声，报完经信箱告诉 0 号结点；
   0 号的那一路是测试台盯着的，另外三路由测试台包装里的接收器按行打进日志，整片测试去日志里找。 */
#include <stdint.h>

#define REG(a) (*(volatile uint32_t *)(a))
#define LSR (*(volatile uint8_t *)0x10000005)
#define CTL 0x40040000u
#define HART REG(CTL + 0x04)
#define RUN REG(CTL + 0x08)
#define TXDEST REG(CTL + 0x100)
#define TXDATA REG(CTL + 0x104)
#define RXSRC REG(CTL + 0x108)
#define RXDATA REG(CTL + 0x10c)
#define STAT REG(CTL + 0x110)

static void putch(char c) {
  while (!(LSR & 0x60)) {}
  REG(0x10000000) = c;
}

static void say(const char *s) {
  while (*s) putch(*s++);
}

/* 等这一路发空：最后一个字还在线上时就去干别的，测试台那头会收到半个 */
static void drain(void) {
  while (!(LSR & 0x40)) {}
}

/* 16550 的驱动初始化时会读写这一路串口别的寄存器（OpenSBI 与 Linux 都会）。片上没有它们：写要有应答、不许当成发字，
   线路状态那个字里的另外三个读回 0 */
static uint32_t others(void) {
  volatile uint8_t *u = (volatile uint8_t *)0x10000000;
  for (int i = 1; i < 8; i++)
    if (i != 5) u[i] = 'Z';
  return u[4] | u[6] | u[7];
}

void on_irq(void) {}

void main(void) {
  uint32_t me = HART;
  if (!me) {
    /* 分频寄存器四路共用，复位后是 1。主频寄存器是 8.8 定点的兆赫，乘 15625/4 得赫兹 */
    uint32_t hz = (REG(0x10000014) & 0xffff) * 15625 / 4;
    REG(0x1000000c) = hz / 115200;
    say("noc uart\n");
    uint32_t seen = others();
    RUN = 0xf;
    for (int i = 0; i < 3; i++) {
      while (!(STAT & 1)) {}
      uint32_t from = RXSRC;
      seen |= (RXDATA == 0x600d0000 + from) << from;
    }
    say(seen == 0xe ? "uart ok 0000000e\n" : "uart BAD\n");
    say("done\n");
  } else {
    say("node ");
    putch('0' + me);
    uint32_t odd = others();
    say(" here\n");
    drain();
    while (!(STAT & 2)) {}
    TXDEST = 0;
    TXDATA = odd ? 0xbad : 0x600d0000 + me;
  }
  for (;;) {}
}
