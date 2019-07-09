# txr2_gm1
Txr2 ported to Gmae Maker 1.4

Pretty much fixed all Game Maker 2.0 specific code like [] to define arrays and the ternary operators.
Includes a minor addition of txr_room_pack to load instance specific creation code when loading rooms.

You can find Game Maker 2.0 code here:
https://bitbucket.org/yal_cc/txr2/src/master/

Sample project from the interpreters guide ( https://yal.cc/interpreters-guide/ , https://yal.cc/r/18/txr2 )

You also need to define a few macros:

txr_error -> global.txr_error_val<br>
txr_parse_tokens -> global.txr_parse_tokens_val<br>
txr_build_list -> global.txr_build_list_val<br>
txr_build_node -> global.txr_build_node_val<br>
txr_build_pos -> global.txr_build_pos_val<br>
txr_build_len -> global.txr_build_len_val<br>
txr_build_can_break -> global.txr_build_can_break_val<br>
txr_build_can_continue -> global.txr_build_can_continue_val<br>
txr_build_locals -> global.txr_build_locals_val<br>
txr_compile_list -> global.txr_compile_list_val<br>
txr_compile_labels -> global.txr_compile_labels_val<br>
txr_function_default -> global.txr_function_default_val<br>
txr_function_error -> global.txr_function_error_val<br>
txr_thread_current -> global.txr_thread_current_val<br>
 
