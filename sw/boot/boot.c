/* to2610-noc 的引导程序：KianV 与 Hazard3 的结点各自从 Flash 的 0x2010_0000 就地执行，照 0x2011_0000 处的目录
 * 找到自己的那份载荷，逐段搬进自己那段 SDRAM 再跳过去，各在自己的串口上报进度。
 * 0 号结点先照目录放开别的结点：各搬各的，不等它。镜像由 sw/pack.py 拼，目录与载荷头的格式写在那里。
 */
#include <stdint.h>

#define REG(a) (*(volatile uint32_t *)(a))
#define LSR (*(volatile uint8_t *)0x10000005)
/* 读到的是这个结点私有段的大小 */
#define MEMSIZE REG(0x10000018)
#define HART REG(0x40040004)
#define RUN REG(0x40040008)
#define FLASH 0x20000000u
#define DIR 0x20110000u
#define RAM 0x80000000u
#define DIR_MAGIC 0x44434f4eu
#define LOAD_MAGIC 0x50434f4eu
#define ZERO 0x80000000u
#define CHUNK 16384u

struct dir {
  uint32_t magic, run, load[4];
};

struct seg {
  uint32_t dest, words;
};

struct head {
  uint32_t magic, nseg, sum, entry;
  struct seg seg[];
};

extern const uint32_t __reloc_start[], __reloc_end[];

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

/* 没活可干：等一个不会来的中断，不在 Flash 里空转占着总线 */
static void park(void) {
  for (;;) __asm__ volatile("wfi");
}

/* 从 Flash 取一条指令要一百多拍，这个循环搬进内存再跑。src 给 0 是清零 */
__attribute__((section(".reloc"), noinline, used)) static uint32_t copy(uint32_t *dst, const uint32_t *src, uint32_t words) {
  uint32_t sum = 0;
  while (words--) {
    uint32_t w = src ? *src++ : 0;
    *dst++ = w;
    sum += w;
  }
  return sum;
}

void main(void) {
  uint32_t me = HART & 3;
  const struct dir *d = (const struct dir *)DIR;
  if (!me) {
    /* 分频寄存器四路串口共用，复位后是 1。主频寄存器是 8.8 定点的兆赫，乘 15625/4 得赫兹；高 16 位是 SD 卡那路 SPI 的分频 */
    uint32_t hz = (REG(0x10000014) & 0xffff) * 15625 / 4;
    REG(0x1000000c) = 4 << 16 | hz / 115200;
    if (d->magic == DIR_MAGIC) RUN = d->run | 1;
  }
  say("\nto2610 boot, node ");
  putch('0' + me);
  putch('\n');

  if (d->magic != DIR_MAGIC || !d->load[me]) {
    say("nothing to load\n");
    park();
  }
  const struct head *h = (const struct head *)(FLASH + d->load[me]);
  if (h->magic != LOAD_MAGIC) {
    say("bad payload at ");
    hex(FLASH + d->load[me]);
    putch('\n');
    park();
  }
  /* 段顶 4 KiB 放搬进内存的拷贝例程，栈在它下面（start.S）；pack.py 不让载荷压到这 8 KiB */
  uint32_t (*fn)(uint32_t *, const uint32_t *, uint32_t) = (void *)(RAM + MEMSIZE - 0x1000);
  uint32_t *p = (uint32_t *)fn;
  for (const uint32_t *s = __reloc_start; s < __reloc_end;) *p++ = *s++;

  const uint32_t *src = (const uint32_t *)&h->seg[h->nseg];
  uint32_t sum = 0;
  say("load ");
  for (uint32_t i = 0; i < h->nseg; i++) {
    uint32_t *dst = (uint32_t *)h->seg[i].dest, n = h->seg[i].words & ~ZERO, zero = h->seg[i].words & ZERO;
    for (uint32_t at = 0; at < n; at += CHUNK) {
      sum += fn(dst + at, zero ? 0 : src + at, n - at < CHUNK ? n - at : CHUNK);
      putch(zero ? 'o' : '.');
    }
    if (!zero) src += n;
  }
  if (sum != h->sum) {
    say("\nsum BAD ");
    hex(sum);
    say(" want ");
    hex(h->sum);
    putch('\n');
    park();
  }
  say("\nsum ok, jump\n");
  /* 每个结点都是自己那个世界里的 0 号 hart：a0 给 0，载荷要知道结点号自己去读控制页 */
  ((void (*)(uint32_t, uint32_t))h->entry)(0, 0);
}
