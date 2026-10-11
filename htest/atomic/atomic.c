/* 四个核在共享的那段 SDRAM 上抢同一个数。直接加会丢数（丢了才说明四个核真的在抢），
   AMO、自旋锁、LR/SC 三种办法各自一个不丢；再看预留会不会被别的核的写作废、私有段是不是各是各的、
   各核的计时器是不是各管各的。0 号核主持，口令与结果走信箱。 */
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

/* CLINT 照标准的排法：mtimecmp 每核 8 字节一格，mtime 共用 */
#define MTIMECMP(h) REG(0x02004000 + 8 * (h))
#define MTIMECMPH(h) REG(0x02004004 + 8 * (h))
#define MTIME REG(0x0200bff8)

enum { RX = 1, ROOM = 2 };
enum { HELLO = 1, GO, DONE, WRITE, MINE, TIMER };
#define KIND(v) ((v) >> 28)
#define BODY(v) ((v) & 0x0fffffff)
#define MSG(k, v) ((uint32_t)(k) << 28 | ((v) & 0x0fffffff))

#define N 200
/* 共享段里的几个字 */
#define S ((volatile uint32_t *)0x90000100)
enum { PLAIN, AMO, LOCK, LOCKED, LRSC, HELD, OTHER };
/* 私有段里的一个字：地址四个核相同，落点各是各的 */
#define P REG(0x80200000)

void arm_timer(void);
/* 预留 p，空转 spins 圈（不碰存储），再条件写 v。写成回 0 */
uint32_t lr_wait_sc(volatile uint32_t *p, uint32_t spins, uint32_t v);

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

static void post(uint32_t to, uint32_t v) {
  while (!(STAT & ROOM)) {}
  TXDEST = to;
  TXDATA = v;
}

static uint32_t wait(uint32_t *from) {
  while (!(STAT & RX)) {}
  *from = RXSRC;
  return RXDATA;
}

static inline uint32_t amoadd(volatile uint32_t *p, uint32_t v) {
  uint32_t r;
  __asm__ volatile("amoadd.w %0, %2, (%1)" : "=&r"(r) : "r"(p), "r"(v) : "memory");
  return r;
}

static inline uint32_t amoswap(volatile uint32_t *p, uint32_t v) {
  uint32_t r;
  __asm__ volatile("amoswap.w %0, %2, (%1)" : "=&r"(r) : "r"(p), "r"(v) : "memory");
  return r;
}

/* 带重试的加一，回重试了几次 */
static uint32_t lrsc_inc(volatile uint32_t *p) {
  uint32_t tries = 0, t, f;
  for (;;) {
    __asm__ volatile("lr.w %0, (%2)\n addi %0, %0, 1\n sc.w %1, %0, (%2)" : "=&r"(t), "=&r"(f) : "r"(p) : "memory");
    if (!f) return tries;
    tries++;
  }
}

/* 每个核各做 N 次；回这一种办法里等了或重来了几次 */
static uint32_t phase(uint32_t which, uint32_t me) {
  uint32_t stat = 0;
  for (uint32_t i = 0; i < N; i++) {
    switch (which) {
      case PLAIN: {
        uint32_t v = S[PLAIN];
        /* 四个核跑同一段循环，步子一样会一直错开；每圈垫的指令数各核不同 */
        for (uint32_t k = 0; k < me; k++) __asm__ volatile("nop");
        S[PLAIN] = v + 1;
        break;
      }
      case AMO:
        amoadd(&S[AMO], 1);
        break;
      case LOCK: {
        while (amoswap(&S[LOCK], 1)) stat++;
        uint32_t v = S[LOCKED];
        for (uint32_t k = 0; k < me; k++) __asm__ volatile("nop");
        S[LOCKED] = v + 1;
        S[LOCK] = 0;
        break;
      }
      case LRSC:
        stat += lrsc_inc(&S[LRSC]);
        break;
    }
  }
  return stat;
}

void on_irq(void) {
  /* 计时器到点：把比较值推到最远，中断就落下去了 */
  uint32_t me = HART;
  MTIMECMPH(me) = 0xffffffff;
  post(0, MSG(TIMER, me));
}

static void worker(uint32_t me) {
  uint32_t from, v;
  post(0, MSG(HELLO, me));
  for (;;) {
    v = wait(&from);
    switch (KIND(v)) {
      case GO:
        post(0, MSG(DONE, phase(BODY(v), me)));
        break;
      case WRITE:
        /* 等 0 号核先把预留做下 */
        for (volatile uint32_t k = 0; k < 20; k++) {}
        S[BODY(v)] = 0x55;
        post(0, MSG(DONE, 0));
        break;
      case MINE:
        if (BODY(v)) P = 0xc0de0000 | me;
        post(0, MSG(DONE, P));
        break;
      case TIMER:
        arm_timer();
        MTIMECMPH(me) = 0;
        MTIMECMP(me) = MTIME + BODY(v);
        break;
    }
  }
}

static void verdict(const char *what, uint32_t bad) {
  say(what);
  say(bad ? " BAD " : " ok ");
  hex(bad);
  putch('\n');
}

/* 四个核一起做一种办法，回总数与等或重来的次数之和 */
static uint32_t together(uint32_t which, uint32_t cell, uint32_t *stat) {
  uint32_t from, v;
  S[cell] = 0;
  for (uint32_t d = 1; d < 4; d++) post(d, MSG(GO, which));
  *stat = phase(which, 0);
  for (int i = 0; i < 3; i++) {
    v = wait(&from);
    *stat += BODY(v);
  }
  return S[cell];
}

static void master(void) {
  uint32_t from, v, bad, sum, stat;

  uint32_t hz = (REG(0x10000014) & 0xffff) * 15625 / 4;
  REG(0x1000000c) = hz / 115200;
  say("noc atomic\n");

  RUN = 0xf;
  bad = 0;
  for (int i = 0; i < 3; i++) bad += KIND(wait(&from)) != HELLO;
  verdict("up", bad);

  sum = together(PLAIN, PLAIN, &stat);
  say("plain ");
  hex(sum);
  putch('\n');
  verdict("lost", sum >= 4 * N || sum < N);

  sum = together(AMO, AMO, &stat);
  verdict("amoadd", sum != 4 * N);

  S[LOCK] = 0;
  sum = together(LOCK, LOCKED, &stat);
  say("waits ");
  hex(stat);
  putch('\n');
  verdict("lock", (sum != 4 * N) + (S[LOCK] != 0) + (stat == 0));

  sum = together(LRSC, LRSC, &stat);
  say("retries ");
  hex(stat);
  putch('\n');
  verdict("lrsc", (sum != 4 * N) + (stat == 0));

  /* 预留着的那个字被 1 号核写了：条件写不成，留下的是它写的数 */
  S[HELD] = 1;
  post(1, MSG(WRITE, HELD));
  bad = lr_wait_sc(&S[HELD], 600, 0x77) == 0;
  wait(&from);
  bad += S[HELD] != 0x55;
  /* 1 号核写的是别的字：预留还在，条件写得成 */
  S[HELD] = 1;
  post(1, MSG(WRITE, OTHER));
  bad += lr_wait_sc(&S[HELD], 600, 0x77) != 0;
  wait(&from);
  bad += S[HELD] != 0x77;
  bad += S[OTHER] != 0x55;
  verdict("reserve", bad);

  /* 同一个地址，四个核各写各的记号再读回来：谁也没盖掉谁 */
  P = 0xc0de0000;
  for (uint32_t d = 1; d < 4; d++) post(d, MSG(MINE, 1));
  bad = 0;
  for (int i = 0; i < 3; i++) {
    v = wait(&from);
    bad += v != MSG(DONE, 0xc0de0000 | from);
  }
  for (uint32_t d = 1; d < 4; d++) post(d, MSG(MINE, 0));
  for (int i = 0; i < 3; i++) {
    v = wait(&from);
    bad += v != MSG(DONE, 0xc0de0000 | from);
  }
  bad += P != 0xc0de0000;
  verdict("private", bad);

  /* 各核的计时器各管各的：三个核各设各的比较值，按远近先后到；0 号核自己的比较值没人动过 */
  post(1, MSG(TIMER, 9000));
  post(2, MSG(TIMER, 3000));
  post(3, MSG(TIMER, 6000));
  bad = 0;
  uint32_t order = 0;
  for (int i = 0; i < 3; i++) {
    v = wait(&from);
    bad += KIND(v) != TIMER || BODY(v) != from;
    order = order << 4 | from;
  }
  bad += order != 0x231;
  bad += MTIMECMP(0) != 0xffffffff || MTIMECMPH(0) != 0xffffffff;
  verdict("timer", bad);

  say("done\n");
}

void main(void) {
  uint32_t me = HART;
  if (me == 0) master();
  else worker(me);
  for (;;) {}
}
