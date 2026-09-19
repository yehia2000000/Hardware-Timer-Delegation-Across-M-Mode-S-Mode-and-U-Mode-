# RISC-V Timer Delegation Lab

Bare-metal RV64 firmware demonstrating hardware timer delegation across
M-mode, S-mode and U-mode on Spike.

A CLINT timer interrupt fires while user code is running and is handled
by the supervisor trap handler. Getting there is less direct than the
assignment sheet suggests, and most of the interesting work is in why.

## Files

| File | Contents |
|---|---|
| `task1.S` | M-mode setup: PMP, delegation, CLINT, `mret` to S-mode |
| `task2.S` | S-mode kernel: `stvec`, `sie`, `sret` to U-mode |
| `task3.S` | Preemption, both timer paths, full verification |
| `task3_clean.S` | Same as `task3.S`, written on top of `riscv_csr.h` |
| `riscv_csr.h` | Shared CSR addresses, bit fields and assembler macros |
| `link.ld` | Loads at `0x80000000`, exports the HTIF mailbox |
| `Makefile` | Build, run, debug, trace |

## Build and run

Requires `riscv64-unknown-elf-gcc` and `spike`.

```sh
make            # build everything
make run1       # Task 1
make run2       # Task 2
make run3a      # Task 3, path A
make run3b      # Task 3, path B
```

Each target prints an exit code. `0` means every assertion in the
firmware passed; `1` means it hit `fail`.

```sh
make debug3b    # interactive Spike debugger
make trace2     # full instruction trace with commit log
make cmp3       # instruction counts, path A vs path B
make task3.i    # preprocessor output, for when a macro misbehaves
```

## What each task does

**Task 1** runs entirely in M-mode. It opens the PMP so S and U mode can
access memory at all, clears `satp` for Bare mode, sets `mideleg[5]` to
delegate the supervisor timer interrupt, programs `mtimecmp`, and drops
to S-mode with `mret`. The S-mode stub then deliberately reads `mstatus`,
which must raise an illegal instruction — that trap is the proof the
privilege drop actually happened.

**Task 2** builds the S-mode kernel: install `stvec`, enable `sie[5]`,
set `sepc` and `sstatus`, and `sret` into a user application. U-mode
reads `sstatus`, traps with cause 2, and the handler verifies
`sstatus.SPP == 0` before skipping the instruction and returning. `SPP`
records the privilege the trap came from, so zero means U-mode and
nothing else.

**Task 3** runs the user loop until the timer preempts it, checks that
`scause` is exactly `0x8000000000000005`, and re-arms for the next tick.
It does this five times, counting how many times M-mode was entered
along the way.

## The two timer paths

The CLINT raises `MTIP` (cause 7). `mideleg[7]` is hardwired to zero —
machine-level interrupts can never be delegated — so that signal is not
connected to the supervisor trap logic at all. For S-mode to be
preempted, `STIP` (cause 5) must rise instead. There are exactly two
ways to make that happen.

**Path A** is what OpenSBI does on hardware without Sstc. The firmware
takes the machine timer interrupt, pushes `mtimecmp` out to clear
`MTIP`, sets `mip.STIP` by hand, and returns. The core then delivers a
supervisor timer interrupt. When the kernel is done it must `ecall` back
into the firmware to clear `STIP`, because `sip.STIP` is read-only from
S-mode. Two entries into M-mode per tick.

**Path B** uses the Sstc extension. M-mode sets `menvcfg.STCE`, and
S-mode programs its own comparator through `stimecmp`. When `mtime`
reaches it, hardware raises `STIP` directly. M-mode never runs.

The firmware probes `menvcfg.STCE` at boot and picks a path at runtime,
so the same binary covers both. Register `s1` counts M-mode entries:
it ends at 10 on path A and 0 on path B.

## Verification registers

Kernel state lives in `s0`-`s11`; U-mode only touches `a0` and `t0`-`t2`,
which is why no handler saves or restores anything. Read these in the
debugger after a run.

| Register | Meaning | Path A | Path B |
|---|---|---|---|
| `s0` | Supervisor timer ticks | 5 | 5 |
| `s1` | M-mode entries | 10 | 0 |
| `s2` | `scause` at first preemption | `0x8000000000000005` | same |
| `s3` | `x10` when first preempted | non-zero | non-zero |
| `s4` | Sstc available | 0 | 1 |
| `s5` | `SPP` at the timer trap | 0 | 0 |
| `s7`, `s10` | `sip` before and after clearing | equal | equal |
| `s8` | `x10` at the last tick | > `s3` | > `s3` |
| `s11` | `scause` of the privilege probe | 2 | 2 |

`s3 < s8` shows the loop resumed after each preemption. `s7 == s10`
shows the attempt to clear `STIP` through `sip` did nothing.

## Two errors in the assignment sheet

The sheet says to set `sstatus.SIE = 1` before `sret`. That bit is
overwritten: `sret` performs `SIE <- SPIE`, so `SPIE` is what must be
set. It happens to work anyway, because an interrupt targeting privilege
`x` is enabled whenever the current privilege is below `x`, regardless of
`xIE` — and the target here is U-mode.

The sheet also says to clear the pending bit through `sip`. Only `SSIP`
is writable through `sip`; `STIP` and `SEIP` are read-only there. The
write raises no exception, it is silently dropped. `task3.S` reads `sip`
before and after the attempt so the result is visible rather than
assumed.

## Notes

If the assembler rejects the CSR instructions, append `_zicsr_zifencei`
to `-march` and to Spike's `--isa`. Zicsr was split out of the base ISA
in newer binutils.

Sources must be `.S` with a capital S, so `gcc` runs the C preprocessor
and `#include` works.

Spike locates the HTIF mailbox by symbol name, which is why `link.ld`
keeps `tohost` and `fromhost`. `tohost = (exit_code << 1) | 1`.