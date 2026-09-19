# assembler directive 
    # ---- CLINT memory map (hart 0) -------------------------------
    .equ CLINT_MTIMECMP,   0x02004000
    .equ CLINT_MTIME,      0x0200BFF8
    .equ TIMER_DELTA,      100000

    # ---- CSR bit fields ------------------------------------------
    .equ MSTATUS_MPP_MASK, (3 << 11)      
    .equ MSTATUS_MPP_S,    (1 << 11)      
    .equ IRQ_S_TIMER,      (1 << 5)      
    .equ EXC_ILLEGAL_INSN, (1 << 2)       
    .equ PMP_NAPOT_RWX,    0x1F           

    # ---- HTIF exit codes -----------------------------------------
    .equ HTIF_PASS,        1             
    .equ HTIF_FAIL,        3             

    .section .text.init, "ax"
    .globl _start

_start:

    la      t0, m_trap_handler
    csrw    mtvec, t0         
    csrw    mie, zero                 
    

    #memory mangement  and protecttion i give the all memory  to s - mode without virtual memory 
    li      t0, -1
    csrw    pmpaddr0, t0
    li      t0, PMP_NAPOT_RWX
    csrw    pmpcfg0, t0
    csrw    satp, zero

    # set up delegation for S-mode timer interrupts and illegal instruction exceptions
    li      t0, IRQ_S_TIMER
    csrs    mideleg, t0
    li      t0, EXC_ILLEGAL_INSN
    csrs    medeleg, t0

    #check if delegation stuck 
    csrr    s1, mideleg               
    andi    t0, s1, IRQ_S_TIMER
    beqz    t0, fail                  

   
    li      t0, CLINT_MTIME
    ld      s2, 0(t0)               
    li      t1, TIMER_DELTA
    add     s3, s2, t1               

    li      t0, CLINT_MTIMECMP
    sd      s3, 0(t0)
    ld      s4, 0(t0)                 

    bne     s3, s4, fail

    # set up the S-mode entry point and switch to S-mode
    la      t0, s_mode
    csrw    mepc, t0

    # clear MPP
    li      t0, MSTATUS_MPP_MASK
    csrc    mstatus, t0         
    # MPP = 01 (S-mode)      
    li      t0, MSTATUS_MPP_S
    csrs    mstatus, t0               

    csrr    s5, mstatus               

    mret

    j       fail                      


# S -Mode 
    .align 2
s_mode:
 
    la      t0, s_priv
    csrw    stvec, t0

    csrr    t1, mstatus               # trap
    j       fail                      # reached only if still in M-mode

# trap handler for S-mode
    .align 2
s_priv:
    csrr    t0, scause                # expect 2 = Illegal Instruction
    li      t1, 2
    bne     t0, t1, fail

    csrr    s7, stval                 # s7 = the offending instruction word
    csrr    s8, sepc                  # s8 = address of the csrr

    li      a0, 0x5                   # marker: S-mode confirmed
    j       pass


# trap handler for M-mode
    .align 2
m_trap_handler:
    csrr    s9,  mcause
    csrr    s10, mepc
    csrr    s11, mtval
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
#  HTIF communication block -- Spike locates these by symbol name
# =====================================================================
    .section .tohost, "aw", @progbits
    .align 6
    .globl tohost
tohost:     .dword 0
    .align 6
    .globl fromhost
fromhost:   .dword 0