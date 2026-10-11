# to2610-noc

Four cores on a two-by-two mesh network, for the ECOS 2610 shuttle: four Hazard3 cores, one on each node, exchange messages through per-core mailboxes and share the off-chip flash, SDRAM and serial port of the [`to2610-kvc`](https://github.com/Tape-Out/to2610-kvc) board.

![maturity](https://img.shields.io/badge/maturity-simulated-yellow) ![license](https://img.shields.io/badge/license-MIT%20OR%20Apache--2.0%20OR%20MulanPSL--2.0-blue)

The cores are upstream's Hazard3, its submodule untouched, taken from [`hazard3`](https://github.com/Tape-Out/hazard3). The mesh is the [`noc`](https://github.com/Tape-Out/noc) library: five-port routers, dimension-order routing, valid/ready links. The memory controllers, the peripherals and the pads are those of `to2610-kvc`, so the chip drops onto the same board.

| File | What |
|:--:|:--:|
| `box/NocBox.bsv` | four mailboxes and a control page in front of the mesh |
| `hwsrc/noc_tile.v` | one node: a Hazard3 core and the bridge from its AHB5 port to the on-chip bus |
| `hwsrc/noc_arb.v` | the four-way arbiter, the private and shared memory windows, and the reservation table for LR, SC and the AMOs |
| `hwsrc/noc_time.v` | the microsecond counter behind `mtime` |
| `patch/noc.patch` | `soc.v` of `to2610-kvc` with the KianV core taken out and the four nodes put in; `patch/mkpatch.py` regenerates it |

The functions, the registers, the pad table, the tests and the limits are in [`docs/流片说明.md`](docs/流片说明.md); the tape-out report is generated from that file.

## The four cores

Only core 0 runs after reset, from the flash at `0x2010_0000`. Writing a bit of `RUN` at `0x4004_0008` releases the matching core, which starts at the same address. All four see the same address map, so one program runs on every core and reads `HART` at `0x4004_0004` to learn which it is.

Each core has 6 MiB of SDRAM of its own at `0x8000_0000`: the address is the same on every core and the memory behind it is not. A further 8 MiB at `0x9000_0000` is shared, and LR, SC and the AMOs are atomic across cores there.

A core sends a word by writing the destination node to `TXDEST` and the word to `TXDATA` at `0x4004_0100`; the receiver reads `RXSRC` and `RXDATA`, and can take an interrupt when a packet arrives. Sending never blocks: when the mesh is full the word is dropped and `STAT` says so.

Only core 0 has the serial port. The others send what they have to say through the mesh and core 0 prints it.

## Testing and tape-out

```console
$ ran run to2610-noc src                  # assemble build/src
$ ran test to2610-noc                     # the chip tests, on the Verilog file that goes to the shuttle
$ ran asic to2610-noc                     # to2610_noc.v, ecc at 50 MHz, report.json
```

The chip tests run on Verilator with pin-level models of the SDRAM, the flash and the UART. `hello` runs on core 0 alone; `box` and `atomic` run one program on all four cores.

## License

任选其一：

- [MIT](LICENSE-MIT)
- [Apache 2.0](LICENSE-APACHE)
- [木兰宽松许可证 第2版](LICENSE-MULAN)

`SPDX-License-Identifier: MIT OR Apache-2.0 OR MulanPSL-2.0`

The upstream sources keep their own licence: Apache-2.0.

除非另行说明，你提交的贡献按上述三者同时授权，不附加其他条件。
