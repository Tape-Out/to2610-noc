/* 回声：信箱里来一个字，加一发回给来的那个结点。两份 Linux 起着的时候，Hazard3 与 PicoRV32 两个结点跑的就是它：
   没有包时睡着等信箱的中断，不占总线。 */
#include <stdint.h>

#define REG(a) (*(volatile uint32_t *)(a))
#define CTL 0x40040000u
#define TXDEST REG(CTL + 0x100)
#define TXDATA REG(CTL + 0x104)
#define RXSRC REG(CTL + 0x108)
#define RXDATA REG(CTL + 0x10c)
#define STAT REG(CTL + 0x110)
#define IE REG(CTL + 0x114)

enum { RX = 1, ROOM = 2 };

void arm_irq(void);
void wait_irq(void);

void on_irq(void) {
  while (STAT & RX) {
    uint32_t from = RXSRC, v = RXDATA;
    while (!(STAT & ROOM)) {}
    TXDEST = from;
    TXDATA = v + 1;
  }
}

void main(void) {
  IE = 1;
  arm_irq();
  for (;;) wait_irq();
}
