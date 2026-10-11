/* to2610-noc 的引导程序：四个核各自从 Flash 的 0x2010_0000 就地执行，把 1 MiB 又 64 KiB 处的载荷搬到
 * 自己那段 SDRAM 的起始处再跳过去，核号放在 a0 里交给载荷。只有 0 号核打字，别的核没有串口。
 * 载荷前面有 16 字节的头：魔数、字节数、按 32 位小端字求的和、保留；与 to2610-kvc 的相同，用它的 pack.py 拼。
 */
#include <stdint.h>

#define REG(a) (*(volatile uint32_t *)(a))
#define LSR (*(volatile uint8_t *)0x10000005)
#define HART REG(0x40040004)
#define PAYLOAD 0x20110000u
#define RAM 0x80000000u
/* 私有的那段 SDRAM 有 6 MiB，顶上 4 KiB 放搬进内存的拷贝例程 */
#define TOP 0x80600000u
#define MAGIC 0x4c50564bu
#define CHUNK 16384u

struct head {
  uint32_t magic, size, sum, pad;
};

extern const uint32_t __reloc_start[], __reloc_end[];

static uint32_t me;

static void putch(char c) {
  if (me) return;
  while (!(LSR & 0x60)) {}
  REG(0x10000000) = c;
}

static void say(const char *s) {
  while (*s) putch(*s++);
}

static void hex(uint32_t v) {
  for (int i = 28; i >= 0; i -= 4) putch("0123456789abcdef"[v >> i & 15]);
}

/* 从 Flash 取一条指令要一百多拍，这个循环搬进内存再跑 */
__attribute__((section(".reloc"), noinline, used)) static uint32_t copy(uint32_t *dst, const uint32_t *src, uint32_t words) {
  uint32_t sum = 0;
  while (words--) {
    uint32_t w = *src++;
    *dst++ = w;
    sum += w;
  }
  return sum;
}

void main(void) {
  me = HART;
  if (!me) {
    /* 分频寄存器复位后是 1。主频寄存器是 8.8 定点的兆赫，乘 15625/4 得赫兹；高 16 位是 SD 卡那路 SPI 的分频 */
    uint32_t hz = (REG(0x10000014) & 0xffff) * 15625 / 4;
    REG(0x1000000c) = 4 << 16 | hz / 115200;
  }
  say("\nto2610 boot\n");

  const struct head *h = (const struct head *)PAYLOAD;
  if (h->magic != MAGIC) {
    say("no payload at 0x20110000\n");
    for (;;) {}
  }
  uint32_t (*fn)(uint32_t *, const uint32_t *, uint32_t) = (void *)(TOP - 0x1000);
  uint32_t *d = (uint32_t *)(TOP - 0x1000);
  for (const uint32_t *s = __reloc_start; s < __reloc_end;) *d++ = *s++;

  uint32_t words = (h->size + 3) / 4, sum = 0;
  say("load ");
  hex(h->size);
  putch(' ');
  for (uint32_t at = 0; at < words; at += CHUNK) {
    uint32_t n = words - at < CHUNK ? words - at : CHUNK;
    sum += fn((uint32_t *)RAM + at, (const uint32_t *)(PAYLOAD + sizeof *h) + at, n);
    putch('.');
  }
  if (sum != h->sum) {
    say("\nsum BAD ");
    hex(sum);
    say(" want ");
    hex(h->sum);
    say("\n");
    for (;;) {}
  }
  say("\nsum ok, jump\n");
  ((void (*)(uint32_t, uint32_t))RAM)(me, 0);
}
