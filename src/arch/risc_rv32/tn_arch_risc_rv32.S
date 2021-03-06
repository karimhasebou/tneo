#include "tn_cfg_dispatch.h"

.section .text



/* External references */
.extern tick_rate
.extern extern_isr_lookup_table
.extern tn_rv32_user_sp
.extern tn_rv32_int_sp
.extern _tn_curr_run_task
.extern _tn_next_task_to_run
.extern _tn_sys_on_context_switch
.extern tn_tick_int_processing


/* Public functions declared in this file */

.global  _tn_arch_context_switch_now_nosave
.global  _tn_arch_context_switch_pend
.global  _tn_arch_is_int_disabled
.global  _tn_arch_inside_isr
.global  tn_arch_sr_save_int_dis
.global  tn_arch_sr_restore
.global  tn_arch_int_dis
.global  tn_arch_int_en
.global  tn_arch_sched_dis_save
.global tn_arch_sched_restore
.global tn_arch_enable_timer

.global tn_save_context
.global load_next_task
.global tn_restore_context

/************************************************************
*   interrupt handlers
*************************************************************

/**
called whenever the system timer reaches 0 and therefore
an interrupt fires to take back control from user thread.

make sure not to write more than 4 instructions within this function
since the interrupt vector can only fit 4 instructions. any additional instruction will  be 
overridden by the code of the next interrupt handler
**/
.global _start
.org 0
_start:
	j	boot_strap



/**.section .ecall_vector **/
/** ecall interrupt handler, not used for now
**/
.org 0x10
_tn_arch_ecall_vector:
    uret
    nop
    nop
    nop

/** .section .ebreak_vector: **/
_tn_arch_ebreak_vector:
    uret
    nop
    nop
    nop

/** .section .timer_vector **/
_tn_arch_timer_vector:
    j tn_timer_timer_handler 
    nop
    nop
    nop
    nop
    
/** .section .extern_int_vector: **/
_tn_arch_extern_int_vector:
    j execute_external_isr
    j execute_external_isr
    j execute_external_isr
    j execute_external_isr
    j execute_external_isr
    j execute_external_isr
    j execute_external_isr
    j execute_external_isr
    j execute_external_isr
    j execute_external_isr
    j execute_external_isr
    j execute_external_isr
    j execute_external_isr
    j execute_external_isr
    j execute_external_isr
    j execute_external_isr

boot_strap:
	li      x4, 0x7 #{eie, tie, gie}
    csrrw   x0,0x4, x4
	lui     sp, %hi(_fstack)
	addi    sp, sp, %lo(_fstack)
	jal     main
	li	    a7, 10
	ecall



/* constants */
.equ context_size, 132
/* registers that gcc does not recognise by name for now */
.equ uie, 0x4
.equ ustatus, 0x42
.equ timer, 0xc01
/* function implementations*/


/** saves context and then uses a lookup table to locate the appropriate isr
**/
execute_external_isr:
    addi sp, sp, -context_size

    #store all general purpose registers to the stack
    sw x1, 0(sp)
    sw x3, 8(sp)
    sw x4, 12(sp)
    sw x5, 16(sp)
    sw x6, 20(sp)
    sw x7, 24(sp)
    sw x8, 28(sp)
    sw x9, 32(sp)
    sw x10, 36(sp)
    sw x11, 40(sp)
    sw x12, 44(sp)
    sw x13, 48(sp)
    sw x14, 52(sp)
    sw x15, 56(sp)
    sw x16, 60(sp)
    sw x17, 64(sp)
    sw x18, 68(sp)
    sw x19, 72(sp)
    sw x20, 76(sp)
    sw x21, 80(sp)
    sw x22, 84(sp)
    sw x23, 88(sp)
    sw x24, 92(sp)
    sw x25, 96(sp)
    sw x26, 100(sp)
    sw x27, 104(sp)
    sw x28, 108(sp)
    sw x29, 112(sp)
    sw x30, 116(sp)
    sw x31, 120(sp)

    /* save task stack pointer and switch to interrupt stack */
    la t0, tn_rv32_user_sp
    sw sp, 0(t0)
    lw sp, tn_rv32_int_sp

    /* find isr responsible to handling the interrupt*/
    csrrw t0, ustatus, x0
    slli t0, t0, 2		# multiply by 4 to account for ptr size
    la t1, extern_isr_lookup_table
    add t1, t1, t0
    lw t1, 0(t1)

    /* jump to the appropriate isr */
    jalr t1 
    
    /* return to user task stack   */
    lw sp, tn_rv32_user_sp 
    j tn_restore_context

/*
* ------------------------------------------------------------------------
* _tn_arch_context_switch_now_nosave()
*
* Called whenever we need to switch context to new task, but don't save
* current context.
*
* Interrupts should be disabled before calling this function.
*
* See comments in tn_arch.h
*/
_tn_arch_context_switch_now_nosave:
    la x5, _tn_curr_run_task            /* x5 = &_tn_curr_run_task */     
    lw x6, _tn_next_task_to_run         /* x6 = _tn_next_task_to_run */


 #if _TN_ON_CONTEXT_SWITCH_HANDLER
     lw a0, 0(x5)                 /* a0 = _tn_curr_run_task */
     add a1, x6, zero             /* a1 =  _tn_next_task_to_run */

    /* 
     * arguments are set:
     * - a0: _tn_curr_run_task
     * - a1: _tn_next_task_to_run
     */
     jal _tn_sys_on_context_switch
 #endif


    lw sp, 0(x6)                        /* set sp to next task's stack */
    sw x6, 0(x5)    /* _tn_curr_run_task = _tn_next_task_to_run */
    jal x0, tn_restore_context


# disables all interrupts unconditionally
tn_arch_int_dis:
    CSRRW zero, 0x4, zero # disable all interrupts
    ret

# enables all interrupts uncondtionally
tn_arch_int_en:
    addi t0, x0, -1 # set all bits to one
    CSRRW x0, 0x4, t0 #  enable gie flag
    ret

/** turns on timer so that kernel can pre-empt tasks every time quantum
*/
tn_arch_enable_timer:
   # sw t0, -4(sp)
    lw t0, tick_rate;
    csrrw x0, 0xc01, t0
    # lw t0, -4(sp)
    ret

/* 
 check if interrupts are disabled
 return 1 if interrupts are disabled, 0 otherwise
 */
_tn_arch_is_int_disabled:
    CSRRW a0,0x4, zero   #read interrupt status
    CSRRW x0,0x4, a0     #restore interrupt status
    andi  a0,a0,0x1      #check if global interrupts are enabled
    xori  a0,a0,0x1      #invert least significant bit
    ret

/*
* ------------------------------------------------------------------------
* perform_context_switch()
* we don't have software interrupts
* its currently called directly when a context switch is pending,
* will find a software workaround to allow pending if problems arise
*/
.macro tn_save_context
    addi sp, sp, -context_size

    #store all general purpose registers to the stack
    sw x1, 0(sp)
    sw x3, 8(sp)
    sw x4, 12(sp)
    sw x5, 16(sp)
    sw x6, 20(sp)
    sw x7, 24(sp)
    sw x8, 28(sp)
    sw x9, 32(sp)
    sw x10, 36(sp)
    sw x11, 40(sp)
    sw x12, 44(sp)
    sw x13, 48(sp)
    sw x14, 52(sp)
    sw x15, 56(sp)
    sw x16, 60(sp)
    sw x17, 64(sp)
    sw x18, 68(sp)
    sw x19, 72(sp)
    sw x20, 76(sp)
    sw x21, 80(sp)
    sw x22, 84(sp)
    sw x23, 88(sp)
    sw x24, 92(sp)
    sw x25, 96(sp)
    sw x26, 100(sp)
    sw x27, 104(sp)
    sw x28, 108(sp)
    sw x29, 112(sp)
    sw x30, 116(sp)
    sw x31, 120(sp)
    # extract tasks pc from epc 
    csrrw x31, 65, zero # read epc without changing epc
    csrrw zero,65, x31 # restore epc that was overriden 
    sw x31, 124(sp) # store pc to resume exec from

    # start switching tasks
    lw a0, _tn_curr_run_task        # a0 = _tn_curr_run_task
    sw sp, 0(a0)                    # store sp in preempted task's TCB

.endm

.macro load_next_task
    la t0, _tn_curr_run_task        # t0 = &_tn_curr_run_task
    lw a0, 0(t0)                    # a0 = _tn_curr_run_task

    lw t1, _tn_next_task_to_run     # t1 = _tn_next_task_to_run
    add a1, t1, zero                # a1 = _tn_next_task_to_run
    lw sp, 0(t1)                    # load sp of task to run

  #if _TN_ON_CONTEXT_SWITCH_HANDLER
      /* 
      * arguments are set:
      * - a0: _tn_curr_run_task
      * - a1: _tn_next_task_to_run
      */
      jal     _tn_sys_on_context_switch
  #endif

    sw  t1, 0(t0)            /* _tn_curr_run_task = _tn_next_task_to_run */

.endm

/* expects everything to be in place, just to load from current sp the context
*/
tn_restore_context:
    
    lw x31, 124(sp) # load epc from process stack
    CSRRW zero, 65, x31 # restore epc and ignore value read

    lw x1, 0(sp)
    lw x3, 8(sp)
    lw x4, 12(sp)
    lw x5, 16(sp)
    lw x6, 20(sp)
    lw x7, 24(sp)
    lw x8, 28(sp)
    lw x9, 32(sp)
    lw x10, 36(sp)
    lw x11, 40(sp)
    lw x12, 44(sp)
    lw x13, 48(sp)
    lw x14, 52(sp)
    lw x15, 56(sp)
    lw x16, 60(sp)
    lw x17, 64(sp)
    lw x18, 68(sp)
    lw x19, 72(sp)
    lw x20, 76(sp)
    lw x21, 80(sp)
    lw x22, 84(sp)
    lw x23, 88(sp)
    lw x24, 92(sp)
    lw x25, 96(sp)
    lw x26, 100(sp)
    lw x27, 104(sp)
    lw x28, 108(sp)
    lw x29, 112(sp)
    lw x30, 116(sp)
    lw x31, 120(sp)
    
    addi sp, sp, context_size # pop all elements used by context switching

    uret


/*
* ------------------------------------------------------------------------
* _tn_arch_context_switch_pend()
*
* Called whenever we need to switch context from one task to another.
* interrupts running task to perform context switch
* See comments in tn_arch.h
*/
_tn_arch_context_switch_pend:
    # todo: verify actual behavior, might need to use specific interrupt code
    # rather than zero for system interrupt code
    
    # la t0, should_context_switch
    # addi t1, zero, 1
    # sw t1, 0(t0)

    ret
    # j perform_context_switch   # perform system interrupt for context switching

/**
* Should return 1 if <i>system ISR</i> is currently running, 0 otherwise.
*
* Refer to the section \ref interrupt_types for details on what is <i>system
* ISR</i>.
* we are returning zero always since
* risc v rv32 does not support nested interrupts
* therefore 
*/
_tn_arch_inside_isr:
# do we have ustatus ?
     add a0, zero, zero
     ret

/* disables all interrupts and 
returns previous content of uie register(status register)
* 
*/
tn_arch_sr_save_int_dis:
    csrrw a0, 0x4, zero
    ret

/* restores status register(uie register)
to the provided value
*/
tn_arch_sr_restore:
    csrrw zero, 0x4, a0
    ret

/*
 * See comments in the file `tn_arch.h`
 */
tn_arch_sched_dis_save:
    csrrw a0, 0x4, x0 # disable all interrupts since 
    # the scheduler isn't using software interrupts
    # for context switching, we might need to add a flag
    # to allow the kernel to run, but avoid performing context switching
    
    # andi a0, a0, 0x2 # make sure to mask unnessary bits
    ret

/*
 * See comments in the file `tn_arch.h`
 */
tn_arch_sched_restore:
    csrrw zero, 0x4, a0 # restore all interrupts to previous state
    ret                 


/* called by timer vector to handle timer interrupt
*/
tn_timer_timer_handler:
    tn_save_context
    
    # switch to interrupt stack
    la t0, tn_rv32_user_sp      
    sw sp, 0(t0)            # update tn_rv32_user_sp such that we know the stack pointer to return to after 
                            # we complete the execution of the kernel
    lw sp, tn_rv32_int_sp   # switch to interrupt stack

    # execute kernel
    jal tn_tick_int_processing
    jal tn_arch_enable_timer

    lw sp, tn_rv32_user_sp  # switch back to task sp to complete context switch

    # execute next task
    load_next_task
    j   tn_restore_context