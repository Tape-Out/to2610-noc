/* 四个核各起一份 FreeRTOS，同一个镜像，各在自己那段 SDRAM 里。0 号核有串口，跑命令行：
 *   id       报这是什么
 *   sum N    把 1 到 N 的平方和切成四段，自己算一段、另外三段经信箱派给三个核，收齐了相加
 *   ps       问另外三个核各自的节拍数，隔几拍再问一次，看它们的调度器是不是都在走
 *   bye      收尾
 * 另外三个核各有一个干活的任务听信箱，一个最低优先级、不让出的任务：只有抢占起作用，干活的才轮得到。
 */
#include <stdint.h>
#include <stddef.h>

#include "FreeRTOS.h"
#include "task.h"

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
enum { HELLO = 1, JOB, RESULT, PING, PONG };
#define KIND(v) ((v) >> 28)
#define BODY(v) ((v) & 0x0fffffff)
#define MSG(k, v) ((uint32_t)(k) << 28 | ((v) & 0x0fffffff))

static uint32_t me;
static volatile uint32_t spins;

static void putch(char c) {
  while (!(LSR & 0x60)) {}
  REG(0x10000000) = c;
}

static void say(const char *s) {
  while (*s) putch(*s++);
}

static void dec(uint32_t v) {
  char b[10];
  int n = 0;
  do b[n++] = '0' + v % 10; while (v /= 10);
  while (n) putch(b[--n]);
}

void rtos_assert(const char *file, int line_no) {
  if (!me) {
    say("\nassert ");
    say(file);
    putch(':');
    dec(line_no);
    putch('\n');
  }
  for (;;) {}
}

void *memset(void *d, int c, size_t n) {
  for (uint8_t *p = d; n--;) *p++ = c;
  return d;
}

void *memcpy(void *d, const void *s, size_t n) {
  const uint8_t *q = s;
  for (uint8_t *p = d; n--;) *p++ = *q++;
  return d;
}

/* 信箱没有空位、没有来包的时候让出一拍，不占着核空转 */
static void post(uint32_t to, uint32_t v) {
  while (!(STAT & ROOM)) vTaskDelay(1);
  TXDEST = to;
  TXDATA = v;
}

static uint32_t wait(uint32_t *from) {
  while (!(STAT & RX)) vTaskDelay(1);
  *from = RXSRC;
  return RXDATA;
}

static uint32_t squares(uint32_t lo, uint32_t hi) {
  uint32_t s = 0;
  for (uint32_t i = lo; i <= hi; i++) s += i * i;
  return s;
}

static void spinner(void *arg) {
  (void)arg;
  for (;;) spins++;
}

static void worker(void *arg) {
  (void)arg;
  uint32_t from, v;
  post(0, MSG(HELLO, me));
  for (;;) {
    v = wait(&from);
    if (KIND(v) == JOB) post(from, MSG(RESULT, squares(BODY(v) >> 14, BODY(v) & 0x3fff)));
    else if (KIND(v) == PING) post(from, MSG(PONG, xTaskGetTickCount()));
  }
}

static int same(const char *a, const char *b, int n) {
  while (n--)
    if (*a++ != *b++) return 0;
  return 1;
}

static void sum(uint32_t n) {
  uint32_t q = n / 4, from, v, total, parts = 1;
  for (uint32_t d = 1; d < 4; d++) post(d, MSG(JOB, (d * q + 1) << 14 | (d == 3 ? n : (d + 1) * q)));
  total = squares(1, q);
  for (int i = 0; i < 3; i++) {
    v = wait(&from);
    if (KIND(v) == RESULT) {
      total += BODY(v);
      parts++;
    }
  }
  say("sum ");
  dec(total);
  say("\nparts ");
  dec(parts);
  putch('\n');
}

static void ps(void) {
  uint32_t from, v, first[4] = {0, 0, 0, 0}, alive = 0;
  for (int round = 0; round < 2; round++) {
    for (uint32_t d = 1; d < 4; d++) post(d, MSG(PING, 0));
    for (int i = 0; i < 3; i++) {
      v = wait(&from);
      if (KIND(v) != PONG) continue;
      if (round == 0) first[from] = BODY(v);
      else alive += BODY(v) > first[from];
    }
    vTaskDelay(5);
  }
  say("ticks ok ");
  dec(alive);
  putch('\n');
}

static void shell(void *arg) {
  (void)arg;
  uint32_t from, v, up = 1;
  char line[16];
  int n = 0;

  RUN = 0xf;
  for (int i = 0; i < 3; i++) {
    v = wait(&from);
    up += KIND(v) == HELLO && BODY(v) == from;
  }
  say("up ");
  dec(up);
  putch('\n');

  for (;;) {
    /* 没收到字时读出来是全 1 */
    uint32_t c = REG(0x10000000);
    if (c == 0xffffffff) {
      vTaskDelay(1);
      continue;
    }
    if (c != '\n') {
      if (n < 15) line[n++] = c;
      continue;
    }
    line[n] = 0;
    if (n == 2 && same(line, "id", 2)) say("noc 2x2, 4 cores\n");
    else if (n > 4 && same(line, "sum ", 4)) {
      uint32_t k = 0;
      for (int i = 4; i < n; i++) k = k * 10 + (line[i] - '0');
      sum(k);
    } else if (n == 2 && same(line, "ps", 2)) ps();
    else if (n == 3 && same(line, "bye", 3)) say(spins > 0 ? "rtos done\n" : "rtos BAD\n");
    else say("what\n");
    n = 0;
  }
}

int main(uint32_t hart) {
  me = hart;
  if (!me) say("FreeRTOS on to2610-noc\n");
  xTaskCreate(me ? worker : shell, "main", 512, NULL, 2, NULL);
  xTaskCreate(spinner, "spin", 256, NULL, 1, NULL);
  vTaskStartScheduler();
  for (;;) {}
}
