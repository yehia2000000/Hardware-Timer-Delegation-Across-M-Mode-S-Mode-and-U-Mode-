   # CLINT memory map 
    .equ CLINT_MTIMECMP,   0x02004000
    .equ CLINT_MTIME,      0x0200BFF8
    .equ TIMER_DELTA,      100000

    .equ CSR_MENVCFG,      0x30A
    .equ CSR_STIMECMP,     0x14D

    .equ MSTATUS_MPP_MASK, (3 << 11)
    .equ MSTATUS_MPP_S,    (1 << 11)      

    .equ SSTATUS_SIE,      (1 << 1)
    .equ SSTATUS_SPIE,     (1 << 5)
    .equ SSTATUS_SPP,      (1 << 8)       

    .equ IRQ_S_TIMER,      (1 << 5)       # mideleg / sie / sip  bit 5
    .equ EXC_ILLEGAL_INSN, (1 << 2)       # medeleg bit 2
    .equ EXC_ECALL_U,      (1 << 8)       # medeleg bit 8 ecall occur from  u mode to  transition to  s mode 

    # cause codes 
    .equ CAUSE_ILLEGAL,    2
    .equ CAUSE_ECALL_U,    8
    .equ CAUSE_S_TIMER,    5

    # misc 
    .equ U_LOOP_LIMIT,     1000000
    .equ HTIF_PASS,        1
    .equ HTIF_FAIL,        3


    .section .text.init, "ax"
    .globl _start

# m MODE 
_start:
    csrw    mie, zero

    # memory protection: allow all of memory to be read/written/executed
    li      t0, -1
    csrw    pmpaddr0, t0 
    li      t0, 0x1F                    # A=NAPOT(3)<<3 | X|W|R
    csrw    pmpcfg0, t0

    csrw    satp, zero                  # Bare mode

    # delegation
    li      t0, IRQ_S_TIMER
    csrs    mideleg, t0                 # STI  -> S-mode
    li      t0, (EXC_ILLEGAL_INSN | EXC_ECALL_U)
    csrs    medeleg, t0                 # illegal insn + ecall-from-U
    csrr    s1, mideleg

  
    #verify  the delegation stuck 
    srli    s9, t1, 63                  # s9 = 1 -> Sstc usable by S-mode

    la      t0, m_trap_handler          # restore the real handler
    csrw    mtvec, t0

    # timer setup: set mtimecmp = mtime + TIMER_DELTA
    li      t0, CLINT_MTIME
    ld      s2, 0(t0)
    li      t1, TIMER_DELTA
    add     s3, s2, t1
    li      t0, CLINT_MTIMECMP
    sd      s3, 0(t0)


    # drop to S-mode 
    la      t0, s_mode_kernel_entry
    csrw    mepc, t0

    li      t0, MSTATUS_MPP_MASK
    csrc    mstatus, t0
    li      t0, MSTATUS_MPP_S
    csrs    mstatus, t0                 # MPP = 01

    mret
    j       fail

# S mode 
    .align 2
s_mode_kernel_entry:


    la      t0, s_mode_trap_handler
    csrw    stvec, t0
    csrr    s4, stvec

    li      t0, IRQ_S_TIMER
    csrs    sie, t0                     # sie.STIE = 1
    csrr    s3, sie                     # expect 0x20

    la      t0, u_mode_user_app
    csrw    sepc, t0

    li      t0, SSTATUS_SPP
    csrc    sstatus, t0                 # SPP = 0
    li      t0, SSTATUS_SPIE
    csrs    sstatus, t0                 # SPIE = 1
    csrr    s2, sstatus

    sret
    
    j       fail                       


#u mode 
    .align 2
u_mode_user_app:
    
    li      t0, 0
    csrr    t0, sstatus

    # workload
    li      a0, 0
    li      a1, U_LOOP_LIMIT

1:  addi    a0, a0, 1
    blt     a0, a1, 1b

    # --- loop finished without preemption: tell the kernel ------------
    ecall                               # scause = 8, traps to stvec
2:  j       2b


#S-mode trap handler 
    .align 2
s_mode_trap_handler:
    csrr    t0, scause

    beq     t0, t1, illegal
    li      t1, CAUSE_ECALL_U
    beq     t0, t1, Lecall
    mv      s10, t0
    j       fail                        # unexpected exception

illegal:
    mv      s5, t0                      # s5 = 2
    csrr    t1, sstatus
    andi    t1, t1, SSTATUS_SPP
    mv      s6, t1                      # s6 = 0  => trap came from U-mode
    bnez    s6, fail                    # SPP = 1 means we never left S

    csrr    t1, sepc                    # skip the faulting csrr
    addi    t1, t1, 4                   # CSR instructions are always 32-bit
    csrw    sepc, t1
    sret

Lecall:
    mv      s8, t0                      # s8 = 8
    mv      s7, a0                      # s7 = final U-mode loop counter
    csrr    t1, sstatus
    andi    t1, t1, SSTATUS_SPP
    bnez    t1, fail                    # ecall must have come from U

    li      a0, 0x2                     # marker: full M -> S -> U chain OK

    j       pass

    .align 2
m_skip_handler:                         # probe helper: skip & continue
    csrr    t0, mepc
    addi    t0, t0, 4
    csrw    mepc, t0
    mret

    .align 2
m_trap_handler:                         # nothing should land here
    csrr    s10, mcause
    csrr    t0,  mepc
    csrr    t1,  mtval
    li      a0, 0xDEAD
    j       fail

pass:
    li      a1, HTIF_PASS
    j       htif_exit
fail:
    li      a1, HTIF_FAIL
htif_exit:
    la      t0, tohost
    sd      a1, 0(t0)
1:  j       1b


# =====================================================================
#  HTIF mailbox
# =====================================================================
    .section .tohost, "aw", @progbits
    .align 6
    .globl tohost
tohost:     .dword 0
    .align 6
    .globl fromhost
fromhost:   .dword 0