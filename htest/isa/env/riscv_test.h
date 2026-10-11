/* riscv-tests 的 p 环境开头有一句把核号不为 0 的核原地停住：它是给多核仿真里只让一个核跑测试用的。
   这里四个核要各跑一遍，把那一句拿掉，别的原样用上游的。 */
#include_next "riscv_test.h"
#undef RISCV_MULTICORE_DISABLE
#define RISCV_MULTICORE_DISABLE
