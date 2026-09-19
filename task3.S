    .equ CLINT_MTIMECMP,   0x02004000
    .equ CLINT_MTIME,      0x0200BFF8
    .equ TIMER_DELTA,      50
    .equ TICKS_WANTED,     5

    .equ CSR_COUNTEREN,     0x306
    .equ CSR_MENVCFG,      0x30A
    .equ CSR_STIMECMP,     0x14D

    .equ MSTATUS_MPP_MASK, (3 << 11)
    .equ MSTATUS_MPP_S,    (1 << 11)

    .equ SSTATUS_SPIE,     (1 << 5)
    .equ SSTATUS_SPP,      (1 << 8)

    .equ IRQ_S_TIMER,      (1 << 5)      # STI  all of these has same index mideleg/mie/sie/mip/sip
    .equ IRQ_M_TIMER,      (1 << 7)      # MTI  mie/mip only
    .equ EXC_ILLEGAL_INSN, (1 << 2)
    .equ EXC_ECALL_U,      (1 << 8)

    .equ CAUSE_ILLEGAL,    2
    .equ CAUSE_ECALL_U,    8
    .equ CAUSE_ECALL_S,    9
    .equ CAUSE_S_TIMER,    5
    .equ CAUSE_M_TIMER,    7

    .equ HTIF_PASS,        1
    .equ HTIF_FAIL,        3


    .section .text.init, "ax"
    .globl _start

#mode M 
_start:
    csrw    mie, zero
    li      s0, 0                       # S-mode tick counter
    li      s1, 0                       # M-mode entry counter

    # protection 
    li      t0, -1
    csrw    pmpaddr0, t0
    li      t0, 0x1F
    csrw    pmpcfg0, t0
    csrw    satp, zero

    #  delegation 
    li      t0, IRQ_S_TIMER
    csrs    mideleg, t0
    li      t0, (EXC_ILLEGAL_INSN | EXC_ECALL_U)
    csrs    medeleg, t0

    li      t1, 0
    li      t0, 1
    slli    t0, t0, 63                  # menvcfg.STCE
    csrs    CSR_MENVCFG, t0

    li      t0, (1 << 1)            # mcounteren.TM
    csrs    CSR_COUNTEREN, t0

    # verify the configuration  enviromnent stuck 
    csrr    t1, CSR_MENVCFG
    srli    s4, t1, 63                  # s4 = 1 -> Sstc, 0 -> classic

    la      t0, m_trap_handler
    csrw    mtvec, t0

    li      t0, CLINT_MTIMECMP
    li      t1, -1
    sd      t1, 0(t0)                   # mtimecmp = 0xFFFF_FFFF_FFFF_FFFF

    la      t0, s_mode_kernel_entry
    csrw    mepc, t0

    li      t0, MSTATUS_MPP_MASK
    csrc    mstatus, t0

    li      t0, MSTATUS_MPP_S
    csrs    mstatus, t0

    mret

    j       fail

#ٍS -mode 
    .align 2
s_mode_kernel_entry:
    la      t0, s_mode_trap_handler
    csrw    stvec, t0                   # Direct mode, 4-byte aligned


    li      t0, CLINT_MTIME
    ld      t1, 0(t0)
    li      t2, TIMER_DELTA
    add     t1, t1, t2
    csrw    CSR_STIMECMP, t1


    li      t0, IRQ_S_TIMER
    csrs    sie, t0                     # sie[5] = mie[5] = 1
    csrr    s9, sie                     # expect 0x20


    la      t0, u_mode_user_app
    csrw    sepc, t0

    li      t0, SSTATUS_SPP
    csrc    sstatus, t0                 # SPP = 0  -> return to U
    li      t0, SSTATUS_SPIE
    csrs    sstatus, t0                 # SPIE = 1 -> SIE = 1 after sret

    sret
    j       fail

    .align 2
u_mode_user_app:

    li      a0, 0
1:  addi    a0, a0, 1                   # x10
    j       1b


    .align 2
s_mode_trap_handler:
    csrr    t0, scause
    bltz    t0, Stimer_check           # bit 63 = 1 -> interrupt

    li      t1, CAUSE_ILLEGAL
    bne     t0, t1, fail

    csrr    t1, sstatus
    andi    t1, t1, SSTATUS_SPP

    bnez    t1, fail                    # SPP must be 0 (came from U)

    csrr    t1, sepc
    addi    t1, t1, 4
    csrw    sepc, t1
    sret

# ---- asynchronous ---------------------------------------------------
Stimer_check:
    addi s0, s0, 1                       # increment the S-mode tick counter                               


    .align 2
m_trap_handler:
    addi    s1, s1, 1                   # <-- the cost counter


# =====================================================================
#  Exit
# =====================================================================
pass:
    li      a1, HTIF_PASS
    j       htif_exit
fail:
    li      a1, HTIF_FAIL
htif_exit:
    la      t0, tohost
    sd      a1, 0(t0)
1:  j       1b


    .section .tohost, "aw", @progbits
    .align 6
    .globl tohost
tohost:     .dword 0
    .align 6
    .globl fromhost
fromhost:   .dword 0