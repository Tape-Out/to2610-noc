/* PicoRV32 那个结点在这一段里的角色：不带 RTOS，就地在 Flash 里跑一个循环，说的是同一套口令：
   报到、算派来的那一段平方和、被问到节拍时回自己那份 CLINT 的毫秒数（它没有调度器，回的是走过的时间）。 */
#include <stdint.h>

#define REG(a) (*(volatile uint32_t *)(a))
#define CTL 0x40040000u
#define HART REG(CTL + 0x04)
#define TXDEST REG(CTL + 0x100)
#define TXDATA REG(CTL + 0x104)
#define RXSRC REG(CTL + 0x108)
#define RXDATA REG(CTL + 0x10c)
#define STAT REG(CTL + 0x110)
#define IE REG(CTL + 0x114)
#define MTIME REG(0x0200bff8)

void arm_irq(void);
void wait_irq(void);

enum { RX = 1, ROOM = 2 };
enum { HELLO = 1, JOB, RESULT, PING, PONG };
#define KIND(v) ((v) >> 28)
#define BODY(v) ((v) & 0x0fffffff)
#define MSG(k, v) ((uint32_t)(k) << 28 | ((v) & 0x0fffffff))

static void post(uint32_t to, uint32_t v) {
  while (!(STAT & ROOM)) {}
  TXDEST = to;
  TXDATA = v;
}

static uint32_t squares(uint32_t lo, uint32_t hi) {
  uint32_t s = 0;
  for (uint32_t i = lo; i <= hi; i++) s += i * i;
  return s;
}

/* 来包中断只管叫醒：在源头关掉，主循环收完再开 */
void on_irq(uint32_t pending) {
  (void)pending;
  IE = 0;
}

void main(void) {
  arm_irq();
  post(0, MSG(HELLO, HART));
  for (;;) {
    /* 没活时等中断，不取指令：存储与外设是四个结点共用的，就地在 Flash 里空转会把别的结点拖慢 */
    while (!(STAT & RX)) {
      IE = 1;
      wait_irq();
    }
    uint32_t from = RXSRC, v = RXDATA;
    if (KIND(v) == JOB) post(from, MSG(RESULT, squares(BODY(v) >> 14, BODY(v) & 0x3fff)));
    else if (KIND(v) == PING) post(from, MSG(PONG, MTIME / 1000));
  }
}
