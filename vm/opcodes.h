#ifndef _INCLUDE_OPCODES_H
#define _INCLUDE_OPCODES_H

#include "vm.h"

typedef enum {
  OP_HALT = 0,
  OP_LOADi = 1,
  OP_LOADs = 2,
  OP_LOADsd = 3,
  OP_LOADc = 4,
  OP_ADD = 5,
  OP_SUB = 6,
  OP_MOVE = 7,
  OP_CALL = 8,
  OP_CALLCL = 9,
  OP_RET = 10,
  OP_MAKECL = 11,
  OP_JMP = 12,
  OP_MATCH = 13
} vm_opcode;

#define instr_size (sizeof(vm_instruction) * 8)
#define __regb 5  /* Number of bits for registers */
#define __opcb 4 /* Number of bits for obcode */


#define get_opcode(instr) ((instr & 0xF0000000) >> (instr_size - __opcb))

#define get_arg_r0(instr) ((instr & 0x0F800000) >> (instr_size - (__opcb + __regb)))
#define get_arg_r1(instr) ((instr & 0x001F0000) >> (instr_size - (__opcb + 2 * __regb)))
#define get_arg_r2(instr) ((instr & 0x0000F800) >> (instr_size - (__opcb + 3 * __regb)))
#define get_arg_i(instr)   (instr & 0x007FFFFF)


/* Uses by tests */
#define instr_ri(op, reg, i) ((op << (instr_size - __opcb)) + (reg << (instr_size - (__opcb + __regb))) + i)
#define instr_rrr(op, reg0, reg1, reg2) ((op << (instr_size - __opcb)) + \
                                            (reg0 << (instr_size - (__opcb + __regb))) + \
                                            (reg1 << (instr_size - (__opcb + 2 * __regb))) + \
                                            (reg2 << (instr_size - (__opcb + 3 * __regb))))

#define op_loadi(r0, i) (instr_ri(OP_LOADi, r0, i))
#define op_loads(r0, i) (instr_ri(OP_LOADs, r0, i))
#define op_loadsd(r0, i) (instr_ri(OP_LOADsd, r0, i))
#define op_loadc(r0, i) (instr_ri(OP_LOADc, r0, i))
#define op_add(r0, r1, r2) (instr_rrr(OP_ADD, r0, r1, r2))
#define op_sub(r0, r1, r2) (instr_rrr(OP_SUB, r0, r1, r2))
#define op_halt (instr_ri(OP_HALT, 0, 0))
#define op_move(r0, r1) (instr_rrr(OP_MOVE, r0, r1, 0))
#define op_call(r0, fr, n) (instr_rrr(OP_CALL, r0, fr, n))
#define op_callcl(r0, fr, n) (instr_rrr(OP_CALLCL, r0, fr, n))
#define op_ret (instr_ri(OP_RET, 0, 0))
#define op_makecl(r0, fr, n) (instr_rrr(OP_MAKECL, r0, fr, n))
#define op_jmp(n) (instr_ri(OP_JMP, 0, n))
#define op_match(r1, r2, r3) (instr_rrr(OP_MATCH, r1, r2, r3))



#endif