/* 四个核跑同一份程序，就地在 Flash 里执行，栈各在自己那段 SDRAM 里。0 号核有串口，是主持的那个；
   其余三个核经信箱听它的口令、把结果发回去，由它代打。 */
#include <stdint.h>

#define REG(a) (*(volatile uint32_t *)(a))
#define LSR (*(volatile uint8_t *)0x10000005)

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

enum { RX = 1, ROOM = 2, DROPPED = 4, NOWHERE = 8 };
/* 载荷的高四位是报文的种类 */
enum { HELLO = 1, SEQ, REPORT, FLOOD, BURST, TALLY, ARM, POKE, ECHO };
#define KIND(v) ((v) >> 28)
#define BODY(v) ((v) & 0x0fffffff)
#define MSG(k, v) ((uint32_t)(k) << 28 | ((v) & 0x0fffffff))

#define PER 20 /* 全对全时每个核给别的每个核发几个 */

void arm_irq(void);

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

static void spin(uint32_t n) {
  for (volatile uint32_t i = 0; i < n; i++) {}
}

/* 发得出去回 1；网格堵着就回 0，由调用的人先去收一收再来 */
static int post(uint32_t to, uint32_t v) {
  if (!(STAT & ROOM)) return 0;
  TXDEST = to;
  TXDATA = v;
  return 1;
}

static int take(uint32_t *from, uint32_t *v) {
  if (!(STAT & RX)) return 0;
  *from = RXSRC;
  *v = RXDATA;
  return 1;
}

/* 全对全的账。别的核动手早的话，口令还没到、它的 SEQ 先到了，所以这本账从一开始就记着；
   0 号核那边，手快的核报完工的 REPORT 也会夹在 SEQ 中间来 */
struct flood {
  uint32_t next[4]; /* 各个源下一个该来的序号 */
  uint32_t got, bad;
  uint32_t reported, theirs; /* 哪几个核报了工，它们报的没对上的个数之和 */
};

static void seq_in(struct flood *f, uint32_t from, uint32_t v) {
  if (KIND(v) == REPORT) {
    f->reported |= 1u << from;
    f->theirs += BODY(v);
    return;
  }
  if (KIND(v) != SEQ || from > 3 || BODY(v) != f->next[from]) f->bad++;
  else f->next[from]++;
  f->got++;
}

static void send(struct flood *f, uint32_t to, uint32_t v) {
  uint32_t from, got;
  while (!post(to, v))
    if (f && take(&from, &got)) seq_in(f, from, got);
}

static void must(uint32_t to, uint32_t v) { send(0, to, v); }

static uint32_t wait(uint32_t *from) {
  uint32_t v;
  while (!take(from, &v)) {}
  return v;
}

/* 全对全：给另外三个核轮着各发 PER 个，自己该收 3 * PER 个。回没对上的个数 */
static uint32_t flood(uint32_t me, struct flood *f) {
  uint32_t from, v;
  for (uint32_t k = 0; k < PER; k++)
    for (uint32_t d = 1; d < 4; d++) send(f, (me + d) & 3, MSG(SEQ, k));
  while (f->got < 3 * PER)
    if (take(&from, &v)) seq_in(f, from, v);
  for (uint32_t s = 0; s < 4; s++) f->bad += s != me && f->next[s] != PER;
  return f->bad;
}

static void zero(struct flood *f) {
  for (uint32_t *p = (uint32_t *)f; p < (uint32_t *)(f + 1); p++) *p = 0;
}

/* 中断里：信箱来了数就加一回给 0 号核；核间中断就清掉自己那一位再报一声 */
void on_irq(void) {
  uint32_t me = HART;
  if (STAT & RX) {
    uint32_t v = RXDATA;
    must(0, MSG(ECHO, BODY(v) + 1));
  } else if (IPI >> me & 1) {
    IPIACK = 1;
    must(0, MSG(ECHO, 0x1b1));
  }
}

static void worker(uint32_t me) {
  struct flood f;
  uint32_t from, v;
  zero(&f);
  must(0, MSG(HELLO, me));
  for (;;) {
    v = wait(&from);
    switch (KIND(v)) {
      case SEQ:
        seq_in(&f, from, v);
        break;
      case FLOOD:
        must(0, MSG(REPORT, flood(me, &f)));
        break;
      case BURST: {
        /* 不看能不能发，连着写：0 号核这会儿压着不收，网格塞满之后的就该丢 */
        TXDEST = 0;
        for (uint32_t i = 0; i < BODY(v); i++) TXDATA = MSG(BURST, i);
        break;
      }
      case TALLY:
        v = STAT;
        STAT = DROPPED;
        must(0, MSG(TALLY, (v & DROPPED) | (STAT & DROPPED) << 4));
        break;
      case ARM:
        IE = 1;
        arm_irq();
        for (;;) __asm__ volatile("wfi");
    }
  }
}

static void verdict(const char *what, uint32_t bad) {
  say(what);
  say(bad ? " BAD " : " ok ");
  hex(bad);
  putch('\n');
}

static void master(void) {
  struct flood f;
  uint32_t from, v, bad, up;
  zero(&f);

  uint32_t hz = (REG(0x10000014) & 0xffff) * 15625 / 4;
  REG(0x1000000c) = hz / 115200;
  say("noc box\n");

  /* 一个核的时候：空着、发给自己、目的号不存在 */
  bad = STAT != ROOM;
  must(0, 0x1234abcd);
  while (!(STAT & RX)) {}
  bad += RXSRC != 0;
  bad += RXDATA != 0x1234abcd;
  bad += STAT != ROOM;
  bad += RXDATA != 0;
  TXDEST = 9;
  TXDATA = 1;
  bad += STAT != (ROOM | NOWHERE);
  STAT = NOWHERE;
  bad += STAT != ROOM;
  verdict("self", bad);

  /* 放开另外三个核，各报一声到 */
  bad = RUN != 1;
  RUN = 0xf;
  bad += RUN != 0xf;
  up = 0;
  for (int i = 0; i < 3; i++) {
    v = wait(&from);
    bad += KIND(v) != HELLO || BODY(v) != from;
    up |= 1u << from;
  }
  bad += up != 0xe;
  verdict("up", bad);

  /* 全对全 */
  for (uint32_t d = 1; d < 4; d++) must(d, MSG(FLOOD, 0));
  bad = flood(0, &f);
  while (f.reported != 0xe)
    if (take(&from, &v)) seq_in(&f, from, v);
  bad += f.theirs + (f.got != 3 * PER);
  verdict("flood", bad);

  /* 压着不收：1 号核连写 40 个，路上装得下的到了，装不下的丢了并记了一笔，写 1 清得掉 */
  must(1, MSG(BURST, 40));
  spin(200);
  uint32_t n = 0, order = 0;
  while (take(&from, &v)) {
    order += from != 1 || KIND(v) != BURST || BODY(v) != n;
    n++;
  }
  bad = order + (n == 0) + (n >= 40);
  must(1, MSG(TALLY, 0));
  v = wait(&from);
  bad += from != 1 || v != MSG(TALLY, DROPPED);
  say("kept ");
  hex(n);
  putch('\n');
  verdict("drop", bad);

  /* 2 号核开中断睡着，来一个包把它叫醒 */
  must(2, MSG(ARM, 0));
  spin(100);
  must(2, MSG(POKE, 0x51));
  v = wait(&from);
  bad = from != 2 || v != MSG(ECHO, 0x52);
  verdict("irq", bad);

  /* 3 号核同样睡着，这回用核间中断叫 */
  must(3, MSG(ARM, 0));
  spin(100);
  bad = IPI != 0;
  IPI = 8;
  v = wait(&from);
  bad += from != 3 || v != MSG(ECHO, 0x1b1);
  bad += IPI != 0;
  verdict("ipi", bad);

  /* 收回 3 号核再放开：它从头来，再报一声到 */
  RUN = 0x7;
  spin(50);
  bad = RUN != 0x7 || (STAT & RX);
  RUN = 0xf;
  v = wait(&from);
  bad += from != 3 || v != MSG(HELLO, 3);
  verdict("again", bad);

  say("done\n");
}

void main(void) {
  uint32_t me = HART;
  if (me == 0) master();
  else worker(me);
  for (;;) {}
}
