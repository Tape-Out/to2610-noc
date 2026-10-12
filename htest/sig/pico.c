/* PicoRV32 那个结点上的签名指令：custom-1（操作码 0x2b），rs1 为 0、1 时读出 "heke"、"1228" 的 ASCII。
   读到的两个字经信箱发给 0 号核，由它当字符串打出来；再核两件事：rs1 为别的数读到 0，custom-1 的别的编码是非法指令。 */
#include <stdint.h>

#define REG(a) (*(volatile uint32_t *)(a))
#define CTL 0x40040000u
#define TXDEST REG(CTL + 0x100)
#define TXDATA REG(CTL + 0x104)
#define STAT REG(CTL + 0x110)

void arm_irq(void);
void wait_irq(void);

static uint32_t sig(uint32_t i) {
  uint32_t r;
  __asm__ volatile(".insn r 0x2b, 0, 0, %0, %1, x0" : "=r"(r) : "r"(i));
  return r;
}

static void tell(uint32_t v) {
  while (!(STAT & 2)) {}
  TXDEST = 0;
  TXDATA = v;
}

/* 程序就地在 Flash 里跑，要改的数放在私有那段 SDRAM 里 */
#define ILLEGAL REG(0x80000000)

/* 第 1 位是非法指令：记一次，返回后从下一条接着走 */
void on_irq(uint32_t pending) {
  if (pending & 2) ILLEGAL++;
}

void main(void) {
  ILLEGAL = 0;
  uint32_t lo = sig(0), hi = sig(1);
  tell(lo);
  tell(hi);
  arm_irq();
  /* 两个字按小端排开是 "heke"、"1228" */
  uint32_t bad = (lo != 0x656b6568) + (hi != 0x38323231) + (sig(2) != 0);
  __asm__ volatile(".insn r 0x2b, 0, 1, x0, x0, x0");
  bad += ILLEGAL != 1;
  tell(bad);
  for (;;) wait_irq();
}
