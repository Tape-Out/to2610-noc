/* riscv-tests 给 PicoRV32 用的环境：它没有机器态的 CSR，上游的 p 环境用不了。
   这里只留测试宏要的那几样：入口、把结果写进 tohost（过了写 1，没过写「第几项」乘 2 加 1，与 p 环境同一个约定）。
   PicoRV32 遇到非法指令或没对齐的访存会停住，那样测试台等不到 tohost，按超时算没过。 */
#ifndef _ENV_PICORV32_H
#define _ENV_PICORV32_H

#define RVTEST_RV32U
#define RVTEST_RV64U
#define TESTNUM gp

#define RVTEST_CODE_BEGIN                                               \
        .section .text.init;                                            \
        .align 6;                                                       \
        .global _start;                                                 \
_start: li TESTNUM, 0;

#define RVTEST_CODE_END

/* 停住用具名的标号：有的测试（fence_i）自己往数字标号处写指令，宏里再用数字标号会被它找错 */
#define RVTEST_PASS                                                     \
        li TESTNUM, 1;                                                  \
        la t5, tohost;                                                  \
        sw TESTNUM, 0(t5);                                              \
.Lpassed: j .Lpassed;

#define RVTEST_FAIL                                                     \
.Lunnumbered: beqz TESTNUM, .Lunnumbered;                               \
        sll TESTNUM, TESTNUM, 1;                                        \
        or TESTNUM, TESTNUM, 1;                                         \
        la t5, tohost;                                                  \
        sw TESTNUM, 0(t5);                                              \
.Lfailed: j .Lfailed;

#define EXTRA_DATA

#define RVTEST_DATA_BEGIN                                               \
        EXTRA_DATA                                                      \
        .pushsection .tohost,"aw",@progbits;                            \
        .align 6; .global tohost; tohost: .word 0, 0;                   \
        .popsection;                                                    \
        .align 4; .global begin_signature; begin_signature:

#define RVTEST_DATA_END .align 4; .global end_signature; end_signature:

#endif
