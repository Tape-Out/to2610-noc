# to2610-noc

Four independent computers on one chip, joined by a two-by-two mesh network, for the ECOS 2610 shuttle: two KianV cores (RV32IMA with Sv32), a Hazard3 (RV32IMAC, machine mode) and a PicoRV32IMAC: upstream's PicoRV32 is RV32IMC and has no A extension, and the one here is our own, written in this repository as a coprocessor on its PCPI port. This is not an SMP system. Every node is hart 0 of its own machine, with its own memory, CLINT and serial port, and each KianV has its own PLIC. The nodes meet in two places only: the mailboxes on the mesh, and a shared stretch of memory where LR, SC and the AMOs hold across all four.

![maturity](https://img.shields.io/badge/maturity-simulated-yellow) ![license](https://img.shields.io/badge/license-MIT%20OR%20Apache--2.0%20OR%20MulanPSL--2.0-blue)

The cores are upstream's, their submodules untouched, taken from [`gf180mcu-kianv-rv32ima-sv32`](https://github.com/Tape-Out/gf180mcu-kianv-rv32ima-sv32), [`hazard3`](https://github.com/Tape-Out/hazard3) and [`picorv32`](https://github.com/Tape-Out/picorv32). The mesh is the [`noc`](https://github.com/Tape-Out/noc) library: five-port routers, dimension-order routing, two buffers per port, valid/ready. Flash, SDRAM and the peripherals of node 0 are those of [`to2610-kvc`](https://github.com/Tape-Out/to2610-kvc).

| File | What |
|:--:|:--:|
| `box/NocBox.bsv` | four mailboxes and a control page in front of the mesh |
| `hwsrc/noc_tile.v` | the Hazard3 node: the core and the bridge from its AHB5 port to the on-chip bus |
| `hwsrc/noc_pico.v` | the PicoRV32IMAC node: the core and our coprocessor, which implements the A extension (`lr.w`, `sc.w` and the nine AMOs), `fence.i` and a signature instruction |
| `hwsrc/noc_arb.v` | the four-way arbiter, the private and shared memory windows, and the reservation table for LR, SC and the AMOs |
| `hwsrc/noc_time.v` | the microsecond counter behind `mtime` |
| `patch/noc.patch` | the source tree of `to2610-kvc` with the four nodes put in: a CLINT, a UART and a memory size for each, a PLIC for each KianV, a 64 MiB SDRAM; `patch/mkpatch.py` regenerates it |
| `sw/boot`, `sw/pack.py` | the boot loader and the packer of the flash image: a directory in flash says which payload each node loads |

The functions, the registers, the pad table, the tests and the limits are in [`docs/流片说明.md`](docs/流片说明.md); the tape-out report is generated from that file.

## The four nodes

All four see the same address map. What differs is what stands behind an address:

| Address | Each node sees |
|:--:|:--:|
| `0x0200_0000` | its own CLINT |
| `0x0C00_0000` | its own PLIC (KianV nodes) |
| `0x1000_0000` | its own UART; `0x1000_0018` reads the size of its private memory |
| `0x2000_0000` | the flash, shared and read-only |
| `0x4004_0000` | the control page: `HART` at `0x04` is the node number, `RUN` at `0x08` releases nodes |
| `0x4004_0100` | its own mailbox |
| `0x8000_0000` | its private SDRAM: 24 MiB for a KianV, 4 MiB for the others |
| `0x9000_0000` | 8 MiB of SDRAM shared by all four |

Only node 0 runs after reset; writing a bit of `RUN` releases the matching node. The KianV and Hazard3 nodes start in the boot loader at `0x2010_0000`. It finds the node's payload in the directory, copies it into the node's own SDRAM, reports on the node's own serial port and jumps to it; on node 0 it first releases the nodes the directory names, so they load side by side. The PicoRV32 starts at `0x2018_0000` and runs its program in place.

```console
$ python3 sw/pack.py boot.bin image.flash --pico pico.bin --run 0xf 01=linux.bin 2=rtos.bin
```

A node sends a word by writing the destination to `TXDEST` and the word to `TXDATA`; the receiver reads `RXSRC` and `RXDATA`. Sending never blocks: when the mesh is full the packet is dropped and a bit of `STAT` says so.

Each node takes its timer and software interrupts from its own CLINT. A packet in the mailbox, an interrupt sent by another node and the node's UART reach a KianV through its PLIC (sources 11, 12 and 10), the Hazard3 on its external interrupt lines, and the PicoRV32 on its interrupts 6, 5 and 7.

Storage is shared, so a node that owns the bus makes the others wait. A program meant to run fast is copied into the node's SDRAM at boot, and an idle node waits for an interrupt instead of spinning in flash.

## The signature instruction

The PicoRV32 node has one instruction of its own, on custom-1: with `rs1` 0 or 1 it returns the two words that spell `heke1228` in memory.

```c
static inline unsigned sig(unsigned i) {
  unsigned r;
  __asm__(".insn r 0x2b, 0, 0, %0, %1, x0" : "=r"(r) : "r"(i));
  return r;
}
unsigned w[3] = {sig(0), sig(1), 0};   /* (char *)w is "heke1228" */
```

## Board

Pads 0 to 53 are those of `to2610-kvc`, and its board fits with the SDRAM replaced by a 64 MiB part in the same package (MT48LC32M16A2 or alike). Pads 54 to 59 are RX and TX of the serial ports of nodes 1 to 3, so every node has a console of its own.

## Testing and tape-out

```console
$ ran run to2610-noc src                  # assemble build/src
$ ran test to2610-noc                     # the chip tests, on the Verilog file that goes to the shuttle
$ ran asic to2610-noc                     # to2610_noc.v, ecc at 50 MHz, report.json
```

The chip tests run on Verilator with pin-level models of the SDRAM, the flash and the four serial ports, each port with a script of its own.

| Test | What |
|:--:|:--:|
| `hello` | node 0 alone: the control page, the edges of the private and shared memory |
| `isa` | riscv-tests on each node, 294 runs |
| `box` | all four exchange numbered packets; drops when the mesh is full; a node taken back and released |
| `irq` | every node raises each of its five interrupts, twenty lines in all, and checks which one the core saw |
| `atomic` | the four kinds of core contend for one counter with AMOs, a spin lock and LR/SC |
| `uart` | each node speaks on its own serial port and on no other |
| `sig` | the signature instruction |
| `rtos` | FreeRTOS on three nodes and a bare-metal worker on the PicoRV32 share out a sum |
| `echo` | one flash image, a different program for each node |

Twenty-two planted design faults each turn one of them red.

## License

任选其一：

- [MIT](LICENSE-MIT)
- [Apache 2.0](LICENSE-APACHE)
- [木兰宽松许可证 第2版](LICENSE-MULAN)

`SPDX-License-Identifier: MIT OR Apache-2.0 OR MulanPSL-2.0`

The upstream sources keep their own licence: Apache-2.0.

除非另行说明，你提交的贡献按上述三者同时授权，不附加其他条件。
