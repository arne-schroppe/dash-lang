#include <stdio.h>
#include "vm_spec.h"

#include "../vm.h"
#include "../opcodes.h"


it( loads_a_number_into_a_register ) {
  vm_instruction program[] = {
    op_loadi(0, 55),
    op_halt
  };
  vm_value result = vm_execute(program, 0);
  is_equal(result, val(55, vm_tag_number));
  is_equal(type_of_value(result), vm_type_number);
}


it( adds_two_numbers ) {
  vm_instruction program[] = {
    op_loadi(1, 5),
    op_loadi(2, 32),
    op_add(0, 1, 2),
    op_halt
  };
  vm_value result = vm_execute(program, 0);
  is_equal(result, 37);
}


it( moves_a_register ) {
  vm_instruction program[] = {
    op_loadi(2, 37),
    op_move(0, 2),
    op_halt
  };
  vm_value result = vm_execute(program, 0);
  is_equal(result, 37);
}


it( directly_calls_a_function ) {
  const int fun_address = 6;
  vm_instruction program[] = {
    op_loadi(1, 15),
    op_loadi(2, 23),
    op_add(4, 1, 2),
    op_loadi(3, fun_address),
    op_call(0, 3, 1), /* result reg, reg with function address, num parameters */
    op_halt,
    op_loadi(2, 100),
    op_add(0, 1, 2),
    op_ret
  };
  vm_value result = vm_execute(program, 0);
  is_equal(result, 138);
}


it( calls_a_closure_downwards ) {
  const int fun_address1 = 6;
  const int fun_address2 = 11;
  vm_instruction program[] = {
    op_loadi(2, fun_address2), //TODO this shouldn't be loadi
    op_loadi(3, 80),
    op_makecl(2, 2, 1),
    op_loadi(1, fun_address1),
    op_call(0, 1, 1), //call fun1 with a closure to fun2
    op_halt,

    // fun1
    op_loadi(2, 115), // addr 6
    op_loadi(3, 23),
    op_add(2, 2, 3),
    op_callcl(0, 1, 1), //closure at register 1 with 1 argument
    op_ret,

    // fun2
    //fun_header(1, 1), /* 1 closed over value, 1 parameter */
    op_sub(0, 1, 2), // addr 11 // reg1 holds the function argument, reg2 is the single env value
    op_ret
  };
  vm_value result = vm_execute(program, 0);
  is_equal(result, 58); //115 + 23 - 80
}


it( calls_a_closure_upwards ) {
  const int fun_address1 = 5;
  const int fun_address2 = 9;
  vm_instruction program[] = {
    op_loadi(1, fun_address1),
    op_call(1, 1, 1),
    op_loadi(2, 80),
    op_callcl(0, 1, 1),
    op_halt,

    // fun 1
    op_loadi(1, fun_address2),
    op_loadi(2, 24),
    op_makecl(0, 1, 1),
    op_ret,

    // fun 2
    op_sub(0, 1, 2),
    op_ret
  };
  vm_value result = vm_execute(program, 0);
  is_equal(result, 56); //80 - 24
}


it( applies_a_number_tag_to_a_value ) {
  vm_value original = 44;
  vm_value number = val(original, vm_tag_number);
  is_equal(type_of_value(number), vm_type_number);
  is_not_equal(type_of_value(number), vm_type_symbol);
  is_equal(from_val(number, vm_tag_number), original);
}


it( applies_a_symbol_tag_to_a_value ) {
  vm_value original = 12;
  vm_value symbol = val(original, vm_tag_symbol);
  is_equal(type_of_value(symbol), vm_type_symbol);
  is_not_equal(type_of_value(symbol), vm_type_number);
  is_equal(from_val(symbol, vm_tag_symbol), original);
}


it( loads_a_symbol_into_a_register ) {
  vm_instruction program[] = {
    op_loads(0, 12),
    op_halt
  };
  vm_value result = vm_execute(program, 0);
  is_equal(result, val(12, vm_tag_symbol));
  is_equal(type_of_value(result), vm_type_symbol);
}


it( loads_a_constant ) {
  vm_value const_table[] = {
    val(33, vm_tag_symbol)
  };

  vm_instruction program[] = {
    op_loadc(0, 0),
    op_halt
  };
  vm_value result = vm_execute(program, const_table);
  is_equal(result, val(33, vm_tag_symbol));
  is_equal(type_of_value(result), vm_type_symbol);
}


it( loads_a_data_symbol ) {
  vm_value const_table[] = {
    /* this would contain the data symbol */
  };

  vm_instruction program[] = {
    op_loadsd(0, 1),
    op_halt
  };
  vm_value result = vm_execute(program, const_table);
  is_equal(result, val(1, vm_tag_data_symbol));
  is_equal(type_of_value(result), vm_type_data_symbol);
}


it( jumps_forward ) {
  vm_instruction program[] = {
    op_loadi(0, 66),
    op_jmp(1),
    op_halt,
    op_loadi(0, 70),
    op_halt
  };
  vm_value result = vm_execute(program, 0);
  is_equal(result, val(70, vm_tag_number));
}


it( matches_a_number ) {
  vm_value const_table[] = {
    match_header(2),
    val(11, vm_tag_number),
    val(22, vm_tag_number),
  };

  vm_instruction program[] = {
    op_loadi(0, 600),
    op_loadi(1, 22), /* value to match */
    op_loadi(2, 0), /* address of match pattern */
    op_match(1, 2, 0),
    op_jmp(1),
    op_jmp(2),
    op_loadi(0, 4),
    op_halt,
    op_loadi(0, 300),
    op_halt
  };
  vm_value result = vm_execute(program, const_table);
  is_equal(result, val(300, vm_tag_number));
}

it( matches_a_symbol ) {
  vm_value const_table[] = {
    match_header(2),
    val(11, vm_tag_symbol),
    val(22, vm_tag_symbol),
  };

  vm_instruction program[] = {
    op_loadi(0, 600),
    op_loads(1, 22), /* value to match */
    op_loadi(2, 0), /* address of match pattern */
    op_match(1, 2, 0),
    op_jmp(1),
    op_jmp(2),
    op_loadi(0, 4),
    op_halt,
    op_loadi(0, 300),
    op_halt
  };
  vm_value result = vm_execute(program, const_table);
  is_equal(result, val(300, vm_tag_number));
}


it( matches_a_data_symbol ) {

  vm_value const_table[] = {
    match_header(2),
    val(3, vm_tag_data_symbol),
    val(6, vm_tag_data_symbol),
    data_symbol_header(1, 2),
    val(55, vm_tag_number),
    val(66, vm_tag_number),
    data_symbol_header(1, 2),
    val(55, vm_tag_number),
    val(77, vm_tag_number),
    data_symbol_header(1, 2), /* the subject */
    val(55, vm_tag_number),
    val(77, vm_tag_number),
  };

  vm_instruction program[] = {
    op_loadi(0, 600),
    op_loadsd(1, 9), /* value to match */
    op_loadi(2, 0), /* address of match pattern */
    op_match(1, 2, 0),
    op_jmp(1),
    op_jmp(2),
    op_loadi(0, 4),
    op_halt,
    op_loadi(0, 300),
    op_halt
  };
  vm_value result = vm_execute(program, const_table);
  is_equal(result, val(300, vm_tag_number));

}

it( binds_a_value_in_a_match ) {

  vm_value const_table[] = {
    match_header(2),
    val(3, vm_tag_data_symbol),
    val(6, vm_tag_data_symbol),
    data_symbol_header(1, 2),
    val(55, vm_tag_number),
    val(66, vm_tag_number),
    data_symbol_header(1, 2),
    val(55, vm_tag_number),
    match_var(1), /* store this match in start_reg + 1 */
    data_symbol_header(1, 2), /* the subject */
    val(55, vm_tag_number),
    val(77, vm_tag_number),
  };

  vm_instruction program[] = {
    op_loadi(0, 600), /* initial wrong value */
    op_loadi(4, 66), /* initial wrong value */

    op_loadsd(1, 9), /* value to match */
    op_loadi(2, 0), /* address of match pattern */
    op_match(1, 2, 3), /* after matching, reg 3 + 1 should contain the matched value (77) */
    op_jmp(1),
    op_jmp(2),
    op_loadi(0, 22), /* case 1 */
    op_halt,
    op_move(0, 4), /* case 2 */
    op_halt
  };

  vm_value result = vm_execute(program, const_table);
  is_equal(result, val(77, vm_tag_number));
}

//TODO
//Fix heap/constant table loading
//create library
//integrate into ocaml part

start_spec(vm_spec)
	example(loads_a_number_into_a_register)
	example(adds_two_numbers)
  example(moves_a_register)
  example(directly_calls_a_function)
  example(calls_a_closure_downwards)
  example(calls_a_closure_upwards)
  example(applies_a_number_tag_to_a_value)
  example(applies_a_symbol_tag_to_a_value)
  example(loads_a_symbol_into_a_register)
  example(loads_a_constant)
  example(loads_a_data_symbol)
  example(jumps_forward)
  example(matches_a_number)
  example(matches_a_symbol)
  example(matches_a_data_symbol)
  example(binds_a_value_in_a_match)
end_spec
