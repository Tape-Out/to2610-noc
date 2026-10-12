/* 每个结点把自己的五路中断各点一次：计时器、软件中断、信箱来包、核间中断、串口。每一路都由结点自己引起，
   中断里按核认到的来路记一笔，认到的不是引起的那一路就算错。来路怎么认各核不同：KianV 是 mcause，外部中断再向
   自己的 PLIC 认领源号；PicoRV32 是中断入口给的位图；Hazard3 的三根外部线并成一路，信箱有包是信箱、核间中断挂着是
   核间中断、都不是就是串口。
   另外三个结点把结果经信箱交给 0 号结点。 */
#include <stdint.h>

#define REG(a) (*(volatile uint32_t *)(a))
#define LSR (*(volatile uint8_t *)0x10000005)
#define MSIP REG(0x02000000)
#define MTIMECMP REG(0x02004000)
#define MTIMECMPH REG(0x02004004)
#define MTIME REG(0x0200bff8)
#define PLIC_EN REG(0x0c002000)
#define PLIC_CLAIM REG(0x0c200004)

#define CTL 0x40040000u
#define HART REG(CTL + 0x04)
#define RUN REG(CTL + 0x08)
#define IPI REG(CTL + 0x0c)
#define IPIACK REG(CTL + 0x10)
#define TXDEST REG(CTL + 0x100)
#define TXDATA REG(CTL + 0x104)
#define RXSRC REG(CTL + 0x108)
#define RXDATA REG(CTL + 0x10c)
#define STAT REG(CTL + 0x110)
#define IE REG(CTL + 0x114)

/* 中断里认到的来路。链接脚本把数据也放在 Flash 里，所以用私有段里一个固定的字 */
#define SEEN REG(0x80000100)

enum { TIMER = 1, SOFT, BOX, IPIS, UART, ODD = 0xe };
/* 五路各占四位，认到的来路都对时拼出来的数 */
#define ALL 0x54321u

void arm_irq(void);
void wait_irq(void);

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

/* why：KianV 与 Hazard3 是 mcause，PicoRV32 是待处理的中断位图 */
void on_irq(uint32_t why) {
  uint32_t src, id = 0;
#ifdef PICO
  src = why == 1 << 3 ? TIMER : why == 1 << 4 ? SOFT : why == 1 << 6 ? BOX : why == 1 << 5 ? IPIS : why == 1 << 7 ? UART : ODD;
#else
  uint32_t me = HART;
  if (why == 0x80000007) src = TIMER;
  else if (why == 0x80000003) src = SOFT;
  else if (why != 0x8000000b) src = ODD;
  else if (me < 2) {
    id = PLIC_CLAIM;
    src = id == 10 ? UART : id == 11 ? BOX : id == 12 ? IPIS : ODD;
  } else src = STAT & 1 ? BOX : IPI >> me & 1 ? IPIS : UART; /* 串口那一路进到这里时多半已经发完，只能靠排除 */
#endif
  /* 把源头按下去，不然一返回又进来 */
  switch (src) {
    case TIMER: MTIMECMPH = 0xffffffff; break;
    case SOFT: MSIP = 0; break;
    case BOX: (void)RXDATA; break;
    case IPIS: IPIACK = 1; break;
    case UART: while (!(LSR & 0x40)) {} break;
  }
  if (id) PLIC_CLAIM = id;
  if (!SEEN) SEEN = src;
}

/* 引起第 s 路，等中断里记下来路；等 50 毫秒没来算没认到 */
static uint32_t probe(uint32_t me, uint32_t s) {
  SEEN = 0;
  /* PLIC 一次只开这一路的源：0 号结点平时打字也会让串口那一路有请求 */
  if (me < 2) PLIC_EN = s == UART ? 1 << 10 : s == BOX ? 1 << 11 : s == IPIS ? 1 << 12 : 0;
  IE = s == BOX;
  switch (s) {
    case TIMER:
      MTIMECMP = MTIME + 100;
      MTIMECMPH = 0;
      break;
    case SOFT: MSIP = 1; break;
    case BOX:
      TXDEST = me;
      TXDATA = s;
      break;
    case IPIS: IPI = 1u << me; break;
    /* 串口那一路在发送期间有请求，发一个换行就够 */
    case UART: REG(0x10000000) = '\n'; break;
  }
  uint32_t t0 = MTIME;
  while (!SEEN && MTIME - t0 < 50000) {}
  return SEEN;
}

static uint32_t all(uint32_t me) {
  uint32_t got = 0;
  arm_irq();
  for (uint32_t s = TIMER; s <= UART; s++) got |= probe(me, s) << 4 * (s - 1);
  if (me < 2) PLIC_EN = 0;
  IE = 0;
  return got;
}

static void verdict(uint32_t node, uint32_t got) {
  putch('n');
  putch('0' + node);
  say(got == ALL ? " ok " : " BAD ");
  hex(got ^ ALL);
  putch('\n');
}

void main(void) {
  uint32_t me = HART;
  if (me) {
    uint32_t got = all(me);
    while (!(STAT & 2)) {}
    TXDEST = 0;
    TXDATA = got;
    for (;;) wait_irq();
  }

  uint32_t hz = (REG(0x10000014) & 0xffff) * 15625 / 4;
  REG(0x1000000c) = hz / 115200;
  /* 这一行的换行由串口那一路的探测补上 */
  say("noc irq");
  while (!(LSR & 0x40)) {}
  verdict(0, all(0));

  RUN = 0xf;
  uint32_t got[4] = {0};
  for (int i = 0; i < 3; i++) {
    while (!(STAT & 1)) {}
    uint32_t from = RXSRC;
    got[from & 3] = RXDATA;
  }
  for (uint32_t d = 1; d < 4; d++) verdict(d, got[d]);
  say("done\n");
  for (;;) {}
}
