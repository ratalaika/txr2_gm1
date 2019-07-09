#define txr_action_write
/// @param action
/// @param buffer
var a = argument0, b/*:Buffer*/ = argument1;
buffer_write(b, buffer_u8, a[0]);
buffer_write(b, buffer_u32, a[1]);
switch (a[0]) {
    case txr_action.number: buffer_write(b, buffer_f64, a[2]); break;
    case txr_action.unop: buffer_write(b, buffer_u8, a[2]); break;
    case txr_action.binop: buffer_write(b, buffer_u8, a[2]); break;
    case txr_action.call:
        buffer_write(b, buffer_string, script_get_name(a[2]));
        buffer_write(b, buffer_u32, a[3]);
        break;
    case txr_action.ret:
    case txr_action.discard:
    case txr_action.jump_pop:
        break;
    case txr_action.jump:
    case txr_action.jump_unless:
    case txr_action.jump_if:
    case txr_action.jump_push:
    case txr_action.band:
    case txr_action.bor:
        buffer_write(b, buffer_s32, a[2]);
        break;
    case txr_action._string:
    case txr_action.set_ident:
    case txr_action.ident:
    case txr_action.get_local:
    case txr_action.set_local:
        buffer_write(b, buffer_string, a[2]);
        break;
    case txr_action._select:
        var w = a[2];
        var n = array_length_1d(w);
        buffer_write(b, buffer_u32, n);
        for (var i = 0; i < n; i++) buffer_write(b, buffer_s32, w[i]);
        buffer_write(b, buffer_s32, a[3]);
        break;
    default:
        show_error(txr_sfmt("Please add a writer for action type % to txr_action_write!", a[0]), 1);
}

#define txr_action_read
/// @param buffer
/// @return action
var b/*:Buffer*/ = argument0;
var t = buffer_read(b, buffer_u8);
var p = buffer_read(b, buffer_u32);
switch (t) {
    case txr_action.number: 
        return txr_a(t, p, buffer_read(b, buffer_f64));
    case txr_action.unop:
    case txr_action.binop:
        return txr_a(t, p, buffer_read(b, buffer_u8));
    case txr_action.call:
        var q = asset_get_index(buffer_read(b, buffer_string));
        return txr_a(t, p, q, buffer_read(b, buffer_u32));
    case txr_action.ret:
    case txr_action.discard:
    case txr_action.jump_pop:
        return txr_a(t, p);
    case txr_action.jump:
    case txr_action.jump_unless:
    case txr_action.jump_if:
    case txr_action.jump_push:
    case txr_action.band:
    case txr_action.bor:
        return txr_a(t, p, buffer_read(b, buffer_s32));
        break;
    case txr_action._string:
    case txr_action.set_ident:
    case txr_action.ident:
    case txr_action.get_local:
    case txr_action.set_local:
        return txr_a(t, p, buffer_read(b, buffer_string));
        break;
    case txr_action._select:
        var n = buffer_read(b, buffer_u32);
        var w = array_create(n);
        for (var i = 0; i < n; i++) w[i] = buffer_read(b, buffer_s32);
        return txr_a(t, p, w, buffer_read(b, buffer_s32));
    default:
        show_error(txr_sfmt("Please add a read for action type % to txr_action_read!", t), 1);
}

#define txr_build
txr_build_list = txr_parse_tokens;
txr_build_pos = 0;
txr_build_len = ds_list_size(txr_build_list) - 1; // (the last item is EOF)
txr_build_can_break = false;
txr_build_can_continue = false;
ds_map_clear(txr_build_locals);
var nodes = txr_a();
var found = 0;
while (txr_build_pos < txr_build_len) {
    if (txr_build_stat()) return true;
    nodes[found++] = txr_build_node;
}
txr_build_node = txr_a(txr_node.block, 0, nodes);
return false;

#define txr_build_expr
/// @param flags
var flags = argument0;
var tk = txr_build_list[|txr_build_pos++];
switch (tk[0]) {
    case txr_token.number: txr_build_node = txr_a(txr_node.number, tk[1], tk[2]); break;
    case txr_token._string: txr_build_node = txr_a(txr_node._string, tk[1], tk[2]); break;
    case txr_token.ident:
        var tkn = txr_build_list[|txr_build_pos];
        if (tkn[0] == txr_token.par_open) { // `ident(`
            txr_build_pos += 1;
            // look up the function
            var args = txr_a(), argc = 0
            var fn = global.txr_function_map[?tk[2]];
            var fn_script, fn_argc;
            if (fn == undefined) {
                fn_script = txr_function_default;
                if (fn_script != -1) {
                    fn_argc = -1;
                    args[argc++] = txr_a(txr_node._string, tk[1], tk[2]);
                } else
                    return txr_throw_at("Unknown function `" + tk[2] + "`", tk);
            } else {
                fn_script = fn[0];
                fn_argc = fn[1];
            }
            // read the arguments and the closing `)`:
            var closed = false;
            while (txr_build_pos < txr_build_len) {
                // hit a closing `)` yet?
                tkn = txr_build_list[|txr_build_pos];
                if (tkn[0] == txr_token.par_close) {
                    txr_build_pos += 1;
                    closed = true;
                    break;
                }
                // read the argument:
                if (txr_build_expr(0)) return true;
                args[argc++] = txr_build_node;
                // skip a `,`:
                tkn = txr_build_list[|txr_build_pos];
                if (tkn[0] == txr_token.comma) {
                    txr_build_pos += 1;
                } else if (tkn[0] != txr_token.par_close) {
                    return txr_throw_at("Expected a `,` or `)`", tkn);
                }
            }
            if (!closed) return txr_throw_at("Unclosed `()` after", tk);
            // find the function, verify argument count, and finally pack up:
            if (fn_argc >= 0 && argc != fn_argc) return txr_throw_at("`" + tk[2] + "` takes "
                + string(fn_argc) + " argument(s), got " + string(argc), tk);
            txr_build_node = txr_a(txr_node.call, tk[1], fn_script, args, fn_argc);
        } else txr_build_node = txr_a(txr_node.ident, tk[1], tk[2]);
        break;
    case txr_token._argument: txr_build_node = txr_a(txr_node._argument, tk[1], tk[2], tk[3]); break;
    case txr_token._argument_count: txr_build_node = txr_a(txr_node._argument_count, tk[1]); break;
    case txr_token.par_open: // (value)
        if (txr_build_expr(0)) return true;
        tk = txr_build_list[|txr_build_pos++];
        if (tk[0] != txr_token.par_close) return txr_throw_at("Expected a `)`", tk);
        break;
    case txr_token.op: // -value, +value
        switch (tk[2]) {
            case txr_op.add:
                if (txr_build_expr(txr_build_flag.no_ops)) return true;
                break;
            case txr_op.sub:
                if (txr_build_expr(txr_build_flag.no_ops)) return true;
                txr_build_node = txr_a(txr_node.unop, tk[1], txr_unop.negate, txr_build_node);
                break;
            default: return txr_throw_at("Expected an expression", tk);
        }
        break;
    case txr_token.unop: // !value
        if (txr_build_expr(txr_build_flag.no_ops)) return true;
        txr_build_node = txr_a(txr_node.unop, tk[1], tk[2], txr_build_node);
        break;
    default: return txr_throw_at("Expected an expression", tk);
}
if ((flags & txr_build_flag.no_ops) == 0) {
    tk = txr_build_list[|txr_build_pos];
    if (tk[0] == txr_token.op) {
        txr_build_pos += 1;
        if (txr_build_ops(tk)) return true;
    }
}
return false;

#define txr_build_loop_body
var could_break = txr_build_can_break;
var could_continue = txr_build_can_continue;
txr_build_can_break = true;
txr_build_can_continue = true;
var trouble = txr_build_stat();
txr_build_can_break = could_break;
txr_build_can_continue = could_continue;
return trouble;

#define txr_build_ops
/// @param first
var nodes = ds_list_create();
ds_list_add(nodes, txr_build_node);
var ops = ds_list_create();
ds_list_add(ops, argument0);
//
var tk;
while (1) {
    // try to read the next expression and add it to list:
    if (txr_build_expr(txr_build_flag.no_ops)) {
        ds_list_destroy(nodes);
        ds_list_destroy(ops);
        return true;
    }
    ds_list_add(nodes, txr_build_node);
    // if followed by an operator, add that too, stop otherwise:
    tk = txr_build_list[|txr_build_pos];
    if (tk[0] == txr_token.op) {
        txr_build_pos++;
        ds_list_add(ops, tk);
    } else break;
}
// Nest operators from top to bottom priority:
var n = ds_list_size(ops);
var pmax = (txr_op.maxp >> 4);
var pri = 0;
while (pri < pmax) {
    for (var i = 0; i < n; i++) {
        tk = ops[|i];
        if ((tk[2] >> 4) != pri) continue;
        nodes[|i] = txr_a(txr_node.binop, tk[1], tk[2], nodes[|i], nodes[|i + 1]);
        ds_list_delete(nodes, i + 1);
        
        ds_list_delete(ops, i);
        n -= 1; i -= 1;
    }
    pri += 1;
}
// Cleanup and return:
txr_build_node = nodes[|0];
ds_list_destroy(nodes);
ds_list_destroy(ops);
return false;

#define txr_build_stat
var tk = txr_build_list[|txr_build_pos++], tkn;
switch (tk[0]) {
    case txr_token.ret: // return <expr>
        if (txr_build_expr(0)) return true;
        txr_build_node = txr_a(txr_node.ret, tk[1], txr_build_node);
        break;
    case txr_token._if: // if <condition-expr> <then-statement> [else <else-statement>]
        if (txr_build_expr(0)) return true;
        var _cond = txr_build_node;
        if (txr_build_stat()) return true;
        var _then = txr_build_node;
        tkn = txr_build_list[|txr_build_pos];
        if (tkn[0] == txr_token._else) { // else <else-statement>
            txr_build_pos += 1;
            if (txr_build_stat()) return true;
            txr_build_node = txr_a(txr_node.if_then_else, tk[1], _cond, _then, txr_build_node);
        } else txr_build_node = txr_a(txr_node.if_then, tk[1], _cond, _then);
        break;
    case txr_token._select: // select func(...) { option <v1>: <x1>; option <v2>: <x2> }
        if (txr_build_expr(0)) return true;
        // verify that it's a vararg function call:
        var _func = txr_build_node;
        if (_func[0] != txr_node.call) return txr_throw_at("Expected a function call", _func);
        if (_func[4] != -1) return txr_throw_at("Function does not accept extra arguments", _func);
        var _args = _func[3];
        var _argc = array_length_1d(_args);
        //
        tkn = txr_build_list[|txr_build_pos++];
        if (tkn[0] != txr_token.cub_open) return txr_throw_at("Expected a `{`", tkn);
        var _opts = txr_a(), _optc = 0;
        var _default = undefined;
        var closed = false;
        while (txr_build_pos < txr_build_len) {
            tkn = txr_build_list[|txr_build_pos++];
            if (tkn[0] == txr_token.cub_close) {
                closed = true;
                break;
            } else if (tkn[0] == txr_token._option || tkn[0] == txr_token._default) {
                var nodes = txr_a(), found = 0;
                if (tkn[0] == txr_token._option) {// option <value>: ...statements
                    if (txr_build_expr(0)) return true;
                    _args[@_argc++] = txr_build_node;
                    _opts[@_optc++] = txr_a(txr_node.block, tk[1], nodes);
                } else { // default: ...statements
                    _default = txr_a(txr_node.block, tk[1], nodes);
                }
                //
                tkn = txr_build_list[|txr_build_pos++];
                if (tkn[0] != txr_token.colon) return txr_throw_at("Expected a `:`", tkn);
                // now read statements until we hit `option` or `}`:
                while (txr_build_pos < txr_build_len) {
                    tkn = txr_build_list[|txr_build_pos];
                    if (tkn[0] == txr_token.cub_close
                        || tkn[0] == txr_token._option
                        || tkn[0] == txr_token._default
                    ) break;
                    if (txr_build_stat()) return true;
                    nodes[@found++] = txr_build_node;
                }
            } else return txr_throw_at("Expected an `option` or `}`", tkn);
        }
        txr_build_node = txr_a(txr_node._select, tk[1], _func, _opts, _default);
        break;
    case txr_token.cub_open: // { ... statements }
        var nodes = txr_a(), found = 0, closed = false;
        while (txr_build_pos < txr_build_len) {
            tkn = txr_build_list[|txr_build_pos];
            if (tkn[0] == txr_token.cub_close) {
                txr_build_pos += 1;
                closed = true;
                break;
            }
            if (txr_build_stat()) return true;
            nodes[@found++] = txr_build_node;
        }
        if (!closed) return txr_throw_at("Unclosed {} starting", tk);
        txr_build_node = txr_a(txr_node.block, tk[1], nodes);
        break;
    case txr_token._while: // while <condition-expr> <loop-expr>
        if (txr_build_expr(0)) return true;
        var _cond = txr_build_node;
        if (txr_build_loop_body()) return true;
        txr_build_node = txr_a(txr_node._while, tk[1], _cond, txr_build_node);
        break;
    case txr_token._do: // do <loop-expr> while <condition-expr>
        if (txr_build_loop_body()) return true;
        var _loop = txr_build_node;
        // expect a `while`:
        tkn = txr_build_list[|txr_build_pos];
        if (tkn[0] != txr_token._while) return txr_throw_at("Expected a `while` after do", tkn);
        txr_build_pos += 1;
        // read condition:
        if (txr_build_expr(0)) return true;
        txr_build_node = txr_a(txr_node.do_while, tk[1], _loop, txr_build_node);
        break;
    case txr_token._for: // for (<init>; <cond-expr>; <post>) <loop>
        // see if there's a `(`:
        tkn = txr_build_list[|txr_build_pos];
        var _par = tkn[0] == txr_token.par_open;
        if (_par) txr_build_pos += 1;
        // read init:
        if (txr_build_stat()) return true;
        var _init = txr_build_node;
        // read condition:
        if (txr_build_expr(0)) return true;
        var _cond = txr_build_node;
        tkn = txr_build_list[|txr_build_pos];
        if (tkn[0] == txr_token.semico) txr_build_pos += 1;
        // read post-statement:
        if (txr_build_stat()) return true;
        var _post = txr_build_node;
        // see if there's a matching `)`?:
        if (_par) {
            tkn = txr_build_list[|txr_build_pos];
            if (tkn[0] != txr_token.par_close) return txr_throw_at("Expected a `)`", tkn);
            txr_build_pos += 1;
        }
        // finally read the loop body:
        if (txr_build_loop_body()) return true;
        txr_build_node = txr_a(txr_node._for, tk[1], _init, _cond, _post, txr_build_node);
        break;
    case txr_token._break:
        if (txr_build_can_break) {
            txr_build_node = txr_a(txr_node._break, tk[1]);
        } else return txr_throw_at("Can't `break` here", tk);
        break;
    case txr_token._continue:
        if (txr_build_can_continue) {
            txr_build_node = txr_a(txr_node._continue, tk[1]);
        } else return txr_throw_at("Can't `continue` here", tk);
        break;
    case txr_token._var:
        var nodes = txr_a(), found = 0;
        do {
            tkn = txr_build_list[|txr_build_pos++];
            if (tkn[0] != txr_token.ident) return txr_throw_at("Expected a variable name", tkn);
            var name = tkn[2];
            tkn = txr_build_list[|txr_build_pos];
            txr_build_locals[?name] = true;
            // check for value:
            if (tkn[0] == txr_token.set) {
                txr_build_pos += 1;
                if (txr_build_expr(0)) return true;
                nodes[found++] = txr_a(txr_node.set, tkn[1],
                    txr_a(txr_node.ident, tkn[1], name), txr_build_node);
            }
            // check for comma:
            tkn = txr_build_list[|txr_build_pos];
            if (tkn[0] == txr_token.comma) {
                txr_build_pos += 1;
            } else break;
        } until (txr_build_pos >= txr_build_len);
        txr_build_node = txr_a(txr_node.block, tk[1], nodes);
        break;
    case txr_token.label:
        tkn = txr_build_list[|txr_build_pos++];
        if (tkn[0] != txr_token.ident) return txr_throw_at("Expected a label name", tkn);
        var name = tkn[2];
        tkn = txr_build_list[|txr_build_pos];
        if (tkn[0] == txr_token.colon) txr_build_pos++; // allow `label some:`
        if (txr_build_stat()) return true;
        txr_build_node = txr_a(txr_node.label, tk[1], name, txr_build_node);
        break;
    case txr_token.jump:
        tkn = txr_build_list[|txr_build_pos++];
        if (tkn[0] != txr_token.ident) return txr_throw_at("Expected a label name", tkn);
        txr_build_node = txr_a(txr_node.jump, tk[1], tkn[2]);
        break;
    case txr_token.jump_push:
        tkn = txr_build_list[|txr_build_pos++];
        if (tkn[0] != txr_token.ident) return txr_throw_at("Expected a label name", tkn);
        txr_build_node = txr_a(txr_node.jump_push, tk[1], tkn[2]);
        break;
    case txr_token.jump_pop: txr_build_node = txr_a(txr_node.jump_pop, tk[1]); break;
    default:
        txr_build_pos -= 1;
        if (txr_build_expr(txr_build_flag.no_ops)) return true;
        var _expr = txr_build_node;
        switch (_expr[0]) {
            case txr_node.call:
                // select expressions are allowed to be statements,
                // and are compiled to `discard <value>` so that we don't clog the stack
                txr_build_node = txr_a(txr_node.discard, _expr[1], txr_build_node);
                break;
            default:
                tkn = txr_build_list[|txr_build_pos];
                if (tkn[0] == txr_token.set) { // node = value
                    txr_build_pos += 1;
                    if (txr_build_expr(0)) return true;
                    txr_build_node = txr_a(txr_node.set, tkn[1], _expr, txr_build_node);
                } else return txr_throw_at("Expected a statement", txr_build_node);
        }
}
// allow a semicolon after statements:
tk = txr_build_list[|txr_build_pos];
if (tk[0] == txr_token.semico) txr_build_pos += 1;

#define txr_compile
/// @param code:string
if (txr_parse(argument0)) return undefined;
if (txr_build()) return undefined;
var out = txr_compile_list;
ds_list_clear(out);
var lbm = txr_compile_labels;
ds_map_clear(lbm);
if (txr_compile_expr(txr_build_node))
    return undefined;
//
var k = ds_map_find_first(lbm);
repeat (ds_map_size(lbm)) {
    var lbs = lbm[?k], lb;
    if (lbs[0] == undefined && array_length_1d(lbs) > 1) {
        lb = lbs[1];
        txr_throw_at("Using undeclared label " + k, lb);
        return undefined;
    }
    var i = array_length_1d(lbs);
    while (--i >= 1) {
        lb = lbs[i];
        lb[@2] = lbs[0];
    }
    k = ds_map_find_next(lbm, k);
}
//
var n = ds_list_size(out);
var arr = array_create(n);
for (var i = 0; i < n; i++) arr[i] = out[|i];
ds_list_clear(out);
return arr;

#define txr_compile_expr
/// @param node
var q = argument0;
var out/*:List*/ = txr_compile_list;

switch (q[0]) {
    case txr_node.number: ds_list_add(out, txr_a(txr_action.number, q[1], q[2])); break;
    case txr_node._string: ds_list_add(out, txr_a(txr_action._string, q[1], q[2])); break;
    case txr_node.ident:
        if (ds_map_exists(txr_build_locals, q[2])) {
            ds_list_add(out, txr_a(txr_action.get_local, q[1], q[2]));
        } else ds_list_add(out, txr_a(txr_action.ident, q[1], q[2]));
        break;
    case txr_node._argument: ds_list_add(out, txr_a(txr_action.get_local, q[1], q[3])); break;
    case txr_node._argument_count: ds_list_add(out, txr_a(txr_action.get_local, q[1], "argument_count")); break;
    case txr_node.unop:
        if (txr_compile_expr(q[3])) return true;
        ds_list_add(out, txr_a(txr_action.unop, q[1], q[2]));
        break;
    case txr_node.binop:
        switch (q[2]) {
            case txr_op.band:
                if (txr_compile_expr(q[3])) return true;
                var jmp = txr_a(txr_action.band, q[1], 0);
                ds_list_add(out, jmp);
                if (txr_compile_expr(q[4])) return true;
                jmp[@2] = ds_list_size(out);
                break;
            case txr_op.bor:
                if (txr_compile_expr(q[3])) return true;
                var jmp = txr_a(txr_action.bor, q[1], 0);
                ds_list_add(out, jmp);
                if (txr_compile_expr(q[4])) return true;
                jmp[@2] = ds_list_size(out);
                break;
            default:
                if (txr_compile_expr(q[3])) return true;
                if (txr_compile_expr(q[4])) return true;
                ds_list_add(out, txr_a(txr_action.binop, q[1], q[2]));
        }
        break;
    case txr_node.call:
        var args = q[3];
        var argc = array_length_1d(args);
        for (var i = 0; i < argc; i++) {
            if (txr_compile_expr(args[i])) return true;
        }
        ds_list_add(out, txr_a(txr_action.call, q[1], q[2], argc));
        break;
    case txr_node.block:
        var nodes = q[2];
        var n = array_length_1d(nodes);
        for (var i = 0; i < n; i++) {
            if (txr_compile_expr(nodes[i])) return true;
        }
        break;
    case txr_node.ret:
        if (txr_compile_expr(q[2])) return true;
        ds_list_add(out, txr_a(txr_action.ret, q[1]));
        break;
    case txr_node.discard:
        if (txr_compile_expr(q[2])) return true;
        ds_list_add(out, txr_a(txr_action.discard, q[1]));
        break;
    case txr_node.if_then: // -> <cond>; jump_unless(l1); <then>; l1:
        if (txr_compile_expr(q[2])) return true;
        var jmp = txr_a(txr_action.jump_unless, q[1], 0);
        ds_list_add(out, jmp);
        if (txr_compile_expr(q[3])) return true;
        jmp[@2] = ds_list_size(out);
        break;
    case txr_node.if_then_else: // -> <cond>; jump_unless(l1); <then>; goto l2; l1: <else>; l2:
        if (txr_compile_expr(q[2])) return true;
        var jmp_else = txr_a(txr_action.jump_unless, q[1], 0);
        ds_list_add(out, jmp_else);
        if (txr_compile_expr(q[3])) return true;
        var jmp_then = txr_a(txr_action.jump, q[1], 0);
        ds_list_add(out, jmp_then);
        jmp_else[@2] = ds_list_size(out);
        if (txr_compile_expr(q[4])) return true;
        jmp_then[@2] = ds_list_size(out);
        break;
    case txr_node._select:
        // select [l1, l2], l3
        // l1: option 1; jump l4
        // l2: option 2; jump l4
        // l3: default
        // l4: ...
        if (txr_compile_expr(q[2])) return true;
        // selector node:
        var opts = q[3];
        var optc = array_length_1d(opts);
        var sel_jmps = array_create(optc);
        var opt_jmps = array_create(optc);
        var sel = txr_a(txr_action._select, q[1], sel_jmps, 0);
        ds_list_add(out, sel);
        // options:
        for (var i = 0; i < optc; i++) {
            sel_jmps[@i] = ds_list_size(out);
            if (txr_compile_expr(opts[i])) return true;
            var jmp = txr_a(txr_action.jump, q[1], 0);
            opt_jmps[@i] = jmp;
            ds_list_add(out, jmp);
        }
        // default;
        sel[@3] = ds_list_size(out);
        if (q[4] != undefined) {
            if (txr_compile_expr(q[4])) return true;
        }
        // point end-of-option jumps to the end of select:
        for (var i = 0; i < optc; i++) {
            var jmp = opt_jmps[i];
            jmp[@2] = ds_list_size(out);
        }
        break;
    case txr_node.set:
        if (txr_compile_expr(q[3])) return true;
        var _expr = q[2];
        switch (_expr[0]) {
            case txr_node.ident:
                if (ds_map_exists(txr_build_locals, _expr[2])) {
                    ds_list_add(out, txr_a(txr_action.set_local, q[1], _expr[2]));
                } else ds_list_add(out, txr_a(txr_action.set_ident, q[1], _expr[2]));
                break;
            default: return txr_throw_at("Expression is not settable", _expr);
        }
        break;
    case txr_node._while:
        // l1: {cont} <condition> jump_unless l2
        var pos_cont = ds_list_size(out);
        if (txr_compile_expr(q[2])) return true;
        var jmp = txr_a(txr_action.jump_unless, q[1], 0);
        ds_list_add(out, jmp);
        // <loop> jump l1
        var pos_start = ds_list_size(out);
        if (txr_compile_expr(q[3])) return true;
        ds_list_add(out, txr_a(txr_action.jump, q[1], pos_cont));
        // l2: {break}
        var pos_break = ds_list_size(out);
        jmp[@2] = pos_break;
        txr_compile_patch_break_continue(pos_start, pos_break, pos_break, pos_cont);
        break;
    case txr_node.do_while:
        // l1: <loop>
        var pos_start = ds_list_size(out);
        if (txr_compile_expr(q[2])) return true;
        // l2: {cont} <condition> jump_if l1
        var pos_cont = ds_list_size(out);
        if (txr_compile_expr(q[3])) return true;
        ds_list_add(out, txr_a(txr_action.jump_if, q[1], pos_start));
        // l3: {break}
        var pos_break = ds_list_size(out);
        txr_compile_patch_break_continue(pos_start, pos_break, pos_break, pos_cont);
        break;
    case txr_node._for:
        if (txr_compile_expr(q[2])) return true;
        // l1: <condition> jump_unless l3
        var pos_loop = ds_list_size(out);
        if (txr_compile_expr(q[3])) return true;
        var jmp = txr_a(txr_action.jump_unless, q[1], 0);
        ds_list_add(out, jmp);
        // <loop>
        var pos_start = ds_list_size(out);
        if (txr_compile_expr(q[5])) return true;
        // l2: {cont} <post> jump l1
        var pos_cont = ds_list_size(out);
        if (txr_compile_expr(q[4])) return true;
        ds_list_add(out, txr_a(txr_action.jump, q[1], pos_loop));
        // l3: {break}
        var pos_break = ds_list_size(out);
        jmp[@2] = pos_break;
        txr_compile_patch_break_continue(pos_start, pos_break, pos_break, pos_cont);
        break;
    case txr_node._break: ds_list_add(out, txr_a(txr_action.jump, q[1], -10)); break;
    case txr_node._continue: ds_list_add(out, txr_a(txr_action.jump, q[1], -11)); break;
    case txr_node.label:
        var lbs = txr_compile_labels[?q[2]];
        if (lbs == undefined) {
            lbs = txr_a(ds_list_size(out));
            txr_compile_labels[?q[2]] = lbs;
        } else lbs[@0] = ds_list_size(out);
        txr_compile_expr(q[3]);
        break;
    case txr_node.jump:
    case txr_node.jump_push:
        var lbs = txr_compile_labels[?q[2]];
        if (lbs == undefined) {
            lbs = txr_a(undefined);
            txr_compile_labels[?q[2]] = lbs;
        }
        var i = txr_action.jump_push;
        if (q[0] == txr_node.jump) i = txr_action.jump;
        var jmp = txr_a(i, q[1], undefined);
        ds_list_add(out, jmp);
        lbs[@array_length_1d(lbs)] = jmp;
        break;
    case txr_node.jump_pop:
        ds_list_add(out, txr_a(txr_action.jump_pop, q[1]));
        break;
    default: return txr_throw_at("Cannot compile node type " + string(q[0]), q);
}
return false;

#define txr_compile_patch_break_continue
/// @param start_pos
/// @param end_pos
/// @param break_pos
/// @param continue_pos
var start = argument0;
var till = argument1;
var _break = argument2;
var _continue = argument3;
var out = txr_compile_list;
for (var i = start; i < till; i++) {
    var act = out[|i];
    if (act[0] == txr_action.jump) switch (act[2]) {
        case -10: if (_break >= 0) act[@2] = _break; break;
        case -11: if (_continue >= 0) act[@2] = _continue; break;
    }
}

#define txr_exec
var arr = argument[0];
var argd = undefined;

if(argument_count > 1) argd = argument[1];
var th/*:txr_thread*/ = txr_thread_create(arr, argd);
var result = undefined;
switch (txr_thread_resume(th)) {
    case txr_thread_status.finished:
        txr_error = "";
        result = th[txr_thread.result];
        break;
    case txr_thread_status.error:
        txr_error = th[txr_thread.result];
        break;
    default:
        txr_error = "Thread paused execution but you are using txr_exec instead of txr_thread_resume";
        break;
}
txr_thread_destroy(th);
return result;

#define txr_function_add
/// @param name
/// @param script
/// @param arg_count
/// Registers a script for use as a function in TXR programs
global.txr_function_map[?argument0] = txr_a(argument1, argument2);

#define txr_init
//!#import "global"
//#macro txr_error global.txr_error_val

// parser:
//#macro txr_parse_tokens global.txr_parse_tokens_val
txr_parse_tokens = ds_list_create();
enum txr_token {
    eof = 0, // <end of file>
    op = 1, // + - * / % div
    par_open = 2, // (
    par_close = 3, // )
    number = 4, // 37
    ident = 5, // some
    comma = 6, // ,
    ret = 7, // return
    _if = 8,
    _else = 9,
    _string = 10, // "hi!"
    cub_open = 11, // {
    cub_close = 12, // }
    set = 13, // =
    unop = 14, // !
    _while = 15,
    _do = 16,
    _for = 17,
    semico = 18, // ;
    _break = 19,
    _continue = 20,
    _var = 21,
    _argument = 22, // argument#
    _argument_count = 23,
    label = 24,
    jump = 25,
    jump_push = 26,
    jump_pop = 27,
    colon = 28,
    _select = 29,
    _option = 30,
    _default = 31,
}
enum txr_op {
    mul  = 1, // *
    fdiv = 2, // /
    fmod = 3, // %
    idiv = 4, // div
    add  = 16, // +
    sub  = 17, // -
    shl  = 32, // <<
    shr  = 33, // >>
    iand = 48, // &
    ior  = 49, // |
    ixor = 50, // ^
    eq   = 64, // ==
    ne   = 65, // !=
    lt   = 66, // <
    le   = 67, // <=
    gt   = 68, // >
    ge   = 69, // >=
    band = 80, // &&
    bor  = 96, // ||
    maxp = 112, // maximum priority
}
var ops/*:txr_op*/ = array_create(txr_op.maxp);//, "an operator");

ops[@txr_op.mul] = "*";
ops[@txr_op.fdiv] = "/";
ops[@txr_op.fmod] = "%";
ops[@txr_op.idiv] = "div"
ops[@txr_op.add] = "+";
ops[@txr_op.sub] = "-";
ops[@txr_op.shl] = "<<";
ops[@txr_op.shr] = ">>";
ops[@txr_op.iand] = "&";
ops[@txr_op.ior] = "|";
ops[@txr_op.ixor] = "^";
ops[@txr_op.eq] = "==";
ops[@txr_op.ne] = "!=";
ops[@txr_op.lt] = "<";
ops[@txr_op.le] = "<=";
ops[@txr_op.gt] = ">";
ops[@txr_op.ge] = ">=";
ops[@txr_op.band] = "&&";
ops[@txr_op.bor] = "||";
global.txr_op_names = ops;


// builder:
//#macro txr_build_list global.txr_build_list_val
//#macro txr_build_node global.txr_build_node_val
//#macro txr_build_pos  global.txr_build_pos_val
//#macro txr_build_len  global.txr_build_len_val
//#macro txr_build_can_break    global.txr_build_can_break_val
//#macro txr_build_can_continue global.txr_build_can_continue_val
//#macro txr_build_locals global.txr_build_locals_val
txr_build_locals = ds_map_create(); // <varname:string, is_local:bool>
global.txr_function_map = ds_map_create(); // <funcname:string, [script, argcount]>
enum txr_node {
    number = 1, // (val:number)
    ident = 2, // (name:string)
    unop = 3, // (unop, node)
    binop = 4, // (binop, a, b)
    call = 5, // (script, args_array)
    block = 6, // (nodes_array) { ...nodes }
    ret = 7, // (node) return <node>
    discard = 8, // (node) - when we don't care
    if_then = 9, // (cond_node, then_node)
    if_then_else = 10, // (cond_node, then_node, else_node)
    _string = 11, // (val:string)
    set = 12, // (node, value:node)
    _while = 13,
    do_while = 14,
    _for = 15,
    _break = 16,
    _continue = 17,
    _argument = 18, // (index:int)
    _argument_count = 19,
    label = 20, // (name:string)
    jump = 21, // (name:string)
    jump_push = 22, // (name:string)
    jump_pop = 23, // ()
    _select = 24, // (call_node, nodes, ?default_node)
}
enum txr_unop {
    negate = 1, // -value
    invert = 2, // !value
}
enum txr_build_flag {
    no_ops = 1
}

// compiler:
//#macro txr_compile_list global.txr_compile_list_val
txr_compile_list = ds_list_create();
//#macro txr_compile_labels global.txr_compile_labels_val
txr_compile_labels = ds_map_create();
enum txr_action {
    number = 1, // (value): push(value)
    ident = 2, // (name): push(self[name])
    unop = 3, // (unop): push(-pop())
    binop = 4, // (op): a = pop(); b = pop(); push(binop(op, a, b))
    call = 5, // (script, argc): 
    ret = 6, // (): return pop()
    discard = 7, // (): pop() - for when we don't care for output
    jump = 8, // (pos): pc = pos
    jump_unless = 9, // (pos): if (!pop()) pc = pos
    _string = 10, // (value:string): push(value)
    set_ident = 11, // (name:string): self[name] = pop()
    band = 12, // (pos): if (peek()) pop(); else pc = pos
    bor = 13, // (pos): if (peek()) pc = pos(); else pop()
    jump_if = 14, // (pos): if (pop()) pc = pos
    get_local = 15, // (name): push(locals[name])
    set_local = 16, // (name): locals[name] = pop()
    jump_push = 17, // (pos): js.push(pc); pc = pos
    jump_pop = 18, // (): pc = js.pop()
    _select = 19, // (pos_array, def_pos): the simplest jumptable
}
//#macro txr_function_default global.txr_function_default_val
txr_function_default = -1;
//#macro txr_function_error global.txr_function_error_val
txr_function_error = undefined;

//#macro txr_thread_current global.txr_thread_current_val
txr_thread_current = undefined;
global.txr_exec_args = ds_list_create();

#define txr_is_number
/// @param value
return is_real(argument0) || is_int64(argument0) || is_bool(argument0) || is_int32(argument0);

#define txr_parse
var str = argument0;
var len = string_length(str);
var out = txr_parse_tokens;
ds_list_clear(out);
var pos = 1;
var line_start = 1;
var line_number = 0;
while (pos <= len)
{
    var start = pos;
    var inf = line_number * 32000 + clamp(pos - line_start, 0, 31999);
    var char = string_ord_at(str, pos);
    pos += 1;
    switch (char)
    {
        case ord(" "):
        //case ord("\t"):
        //case ord('\r'):
            break;
        case ord("\n"): line_number++; line_start = pos; break;
        case ord(";"): ds_list_add(out, txr_a(txr_token.semico, inf)); break;
        case ord(":"): ds_list_add(out, txr_a(txr_token.colon, inf)); break;
        case ord("("): ds_list_add(out, txr_a(txr_token.par_open, inf)); break;
        case ord(")"): ds_list_add(out, txr_a(txr_token.par_close, inf)); break;
        case ord("{"): ds_list_add(out, txr_a(txr_token.cub_open, inf)); break;
        case ord("}"): ds_list_add(out, txr_a(txr_token.cub_close, inf)); break;
        case ord(","): ds_list_add(out, txr_a(txr_token.comma, inf)); break;
        case ord("+"): ds_list_add(out, txr_a(txr_token.op, inf, txr_op.add)); break;
        case ord("-"): ds_list_add(out, txr_a(txr_token.op, inf, txr_op.sub)); break;
        case ord("*"): ds_list_add(out, txr_a(txr_token.op, inf, txr_op.mul)); break;
        case ord("/"):
            switch (string_ord_at(str, pos)) {
                case ord("/"): // line comment
                    while (pos <= len) {
                        char = string_ord_at(str, pos);
                        if (char == ord("\r") || char == ord("\n")) break;
                        pos += 1;
                    }
                    break;
                case ord("*"): // block comment
                    pos += 1;
                    while (pos <= len) {
                        if (string_ord_at(str, pos) == ord("*")
                        && string_ord_at(str, pos + 1) == ord("/")) {
                            pos += 2;
                            break;
                        }
                        pos += 1;
                    }
                    break;
                default: ds_list_add(out, txr_a(txr_token.op, inf, txr_op.fdiv));
            }
            break;
        case ord("%"): ds_list_add(out, txr_a(txr_token.op, inf, txr_op.fmod)); break;
        case ord("!"):
            if (string_ord_at(str, pos) == ord("=")) { // !=
                pos += 1;
                ds_list_add(out, txr_a(txr_token.op, inf, txr_op.ne));
            } else ds_list_add(out, txr_a(txr_token.unop, inf, txr_unop.invert));
            break;
        case ord("="):
            if (string_ord_at(str, pos) == ord("=")) { // ==
                pos += 1;
                ds_list_add(out, txr_a(txr_token.op, inf, txr_op.eq));
            } else ds_list_add(out, txr_a(txr_token.set, inf));
            break;
        case ord("<"):
            switch (string_ord_at(str, pos)) {
                case ord("="): // <=
                    pos += 1;
                    ds_list_add(out, txr_a(txr_token.op, inf, txr_op.le));
                    break;
                case ord("<"): // <<
                    pos += 1;
                    ds_list_add(out, txr_a(txr_token.op, inf, txr_op.shl));
                    break;
                default:
                    ds_list_add(out, txr_a(txr_token.op, inf, txr_op.lt));
            }
            break;
        case ord(">"):
            switch (string_ord_at(str, pos)) {
                case ord("="): // >=
                    pos += 1;
                    ds_list_add(out, txr_a(txr_token.op, inf, txr_op.ge));
                    break;
                case ord(">"): // >>
                    pos += 1;
                    ds_list_add(out, txr_a(txr_token.op, inf, txr_op.shr));
                    break;
                default:
                    ds_list_add(out, txr_a(txr_token.op, inf, txr_op.gt));
            }
            break;
        case ord("'"): case ord('"'): // ord('"') in GMS1
            while (pos <= len) {
                if (string_ord_at(str, pos) == char) break;
                pos += 1;
            }
            if (pos <= len) {
                pos += 1;
                ds_list_add(out, txr_a(txr_token._string, inf,
                    string_copy(str, start + 1, pos - start - 2)));
            } else return txr_throw("Unclosed string starting", txr_print_pos(inf));
            break;
        case ord("|"):
            if (string_ord_at(str, pos) == ord("|")) { // ||
                pos += 1;
                ds_list_add(out, txr_a(txr_token.op, inf, txr_op.bor));
            } else ds_list_add(out, txr_a(txr_token.op, inf, txr_op.ior));
            break;
        case ord("&"):
            if (string_ord_at(str, pos) == ord("&")) { // &&
                pos += 1;
                ds_list_add(out, txr_a(txr_token.op, inf, txr_op.band));
            } else ds_list_add(out, txr_a(txr_token.op, inf, txr_op.iand));
            break;
        case ord("^"): ds_list_add(out, txr_a(txr_token.op, inf, txr_op.ixor)); break;
        default:
            if (char >= ord("0") && char <= ord("9")) {
                var pre_dot = true;
                while (pos <= len) {
                    char = string_ord_at(str, pos);
                    if (char == ord(".")) {
                        if (pre_dot) {
                            pre_dot = false;
                            pos += 1;
                        } else break;
                    } else if (char >= ord("0") && char <= ord("9")) {
                        pos += 1;
                    } else break;
                }
                var val = real(string_copy(str, start, pos - start));
                ds_list_add(out, txr_a(txr_token.number, inf, val));
            }
            else if (char == ord("_")
                || (char >= ord("a") && char <= ord("z"))
                || (char >= ord("A") && char <= ord("Z"))
            ) {
                while (pos <= len) {
                    char = string_ord_at(str, pos);
                    if (char == ord("_")
                        || (char >= ord("0") && char <= ord("9"))
                        || (char >= ord("a") && char <= ord("z"))
                        || (char >= ord("A") && char <= ord("Z"))
                    ) {
                        pos += 1;
                    } else break;
                }
                var name = string_copy(str, start, pos - start);
                switch (name) {
                    case "true": ds_list_add(out, txr_a(txr_token.number, inf,true)); break;
                    case "false": ds_list_add(out, txr_a(txr_token.number, inf,false)); break;
                    case "mod": ds_list_add(out, txr_a(txr_token.op, inf, txr_op.fmod)); break;
                    case "div": ds_list_add(out, txr_a(txr_token.op, inf, txr_op.idiv)); break;
                    case "if": ds_list_add(out, txr_a(txr_token._if, inf)); break;
                    case "else": ds_list_add(out, txr_a(txr_token._else, inf)); break;
                    case "return": ds_list_add(out, txr_a(txr_token.ret, inf)); break;
                    case "while": ds_list_add(out, txr_a(txr_token._while, inf)); break;
                    case "do": ds_list_add(out, txr_a(txr_token._do, inf)); break;
                    case "for": ds_list_add(out, txr_a(txr_token._for, inf)); break;
                    case "break": ds_list_add(out, txr_a(txr_token._break, inf)); break;
                    case "continue": ds_list_add(out, txr_a(txr_token._continue, inf)); break;
                    case "var": ds_list_add(out, txr_a(txr_token._var, inf)); break;
                    case "argument_count": ds_list_add(out, txr_a(txr_token._argument_count, inf)); break;
                    case "label": ds_list_add(out, txr_a(txr_token.label, inf)); break;
                    case "jump": ds_list_add(out, txr_a(txr_token.jump, inf)); break;
                    case "call": ds_list_add(out, txr_a(txr_token.jump_push, inf)); break;
                    case "back": ds_list_add(out, txr_a(txr_token.jump_pop, inf)); break;
                    case "select": ds_list_add(out, txr_a(txr_token._select, inf)); break;
                    case "option": ds_list_add(out, txr_a(txr_token._option, inf)); break;
                    case "default": ds_list_add(out, txr_a(txr_token._default, inf)); break;
                    default:
                        if (string_length(name) > 8 && string_copy(name, 1, 8) == "argument") {
                            var sfx = string_delete(name, 1, 8); // substring(8) in non-GML
                            if (string_digits(sfx) == sfx) {
                                ds_list_add(out, txr_a(txr_token._argument, inf, real(sfx), name));
                                break;
                            }
                        }
                        ds_list_add(out, txr_a(txr_token.ident, inf, name));
                        break;
                }
            }
            else {
                ds_list_clear(out);
                return txr_throw("Unexpected character `" + chr(char) + "`", txr_print_pos(inf));
            }
    }
}
ds_list_add(out, txr_a(txr_token.eof, string_length(str)));
return false;

#define txr_print_pos
var p = argument0;
var c = p % 32000;
var cs; if (c >= 31999) cs = ".."; else cs = string(c + 1);
return "line " + string(1 + (p - c) / 32000) + ", col " + cs;

#define txr_program_read
/// @param buffer
var b/*:Buffer*/ = argument0;
var n = buffer_read(b, buffer_u32);
var w = array_create(n);
for (var i = 0; i < n; i++) {
    w[i] = txr_action_read(b);
}
return w;

#define txr_program_write
/// @param program
/// @param buffer
var w = argument0, b/*:Buffer*/ = argument1;
var n = array_length_1d(w);
buffer_write(b, buffer_u32, n);
for (var i = 0; i < n; i++) {
    txr_action_write(w[i], b);
}
return b;

#define txr_roompack_eval
/// txr_roompack_eval(code)

var code = argument0;
show_debug_message("Room loaded: " + code);
var pg = txr_compile(code);
if (pg == undefined)
    show_error(txr_error, false);
var th = txr_thread_create(pg);
if (txr_thread_resume(th) == txr_thread_status.error) {
    show_error(th, false);
}



#define txr_sfmt
/// @description txr_sfmt(format, ...values)
/// @param format
/// @param  ...values
// sfmt("%/% hp", 1, 2) -> "1/2 hp"
gml_pragma("global", '
    global.txr_sfmt_buf = buffer_create(1024, buffer_grow, 1);
    global.txr_sfmt_map = ds_map_create();
');
var f = argument[0];
var w = global.txr_sfmt_map[?f], i, n;
if (w == undefined) {
    w[0] = "";
    global.txr_sfmt_map[?f] = w;
    i = string_pos("%", f);
    n = 0;
    while (i) {
        w[n++] = string_copy(f, 1, i - 1);
        f = string_delete(f, 1, i);
        i = string_pos("%", f);
    }
    w[n++] = f;
} else n = array_length_1d(w);
//
var b = global.txr_sfmt_buf;
buffer_seek(b, buffer_seek_start, 0);
buffer_write(b, buffer_text, w[0]);
var m = argument_count;
for (i = 1; i < n; i++) {
    if (i < m) {
        f = string(argument[i]);
        if (f != "") buffer_write(b, buffer_text, f);
    }
    f = w[i];
    if (f != "") buffer_write(b, buffer_text, f);
}
buffer_write(b, buffer_u8, 0);
buffer_seek(b, buffer_seek_start, 0);
return buffer_read(b, buffer_string);

#define txr_thread_create
/// @param actions
/// @param ?arguments:array|ds_map
var arr = argument[0];
var argd = undefined;
if (argument_count > 1) argd = argument[1];
var th/*:txr_thread*/ = array_create(txr_thread.sizeof);
th[@txr_thread.actions] = arr;
th[@txr_thread.pos] = 0;
th[@txr_thread.stack] = ds_stack_create();
th[@txr_thread.jumpstack] = ds_stack_create();
var locals = ds_map_create();
if (argd != undefined) {
    if (is_array(argd)) { // an array of arguments
        var i = array_length_1d(argd);
        locals[?"argument_count"] = i;
        locals[?"argument"] = argd;
        while (--i >= 0) locals[?"argument" + string(i)] = argd[i];
    } else { // a ds_map with initial local scope
        ds_map_copy(locals, argd);
    }
}
th[@txr_thread.locals] = locals;
th[@txr_thread.status] = txr_thread_status.running;
return th;
enum txr_thread {
    actions,
    pos,
    //
    stack,
    jumpstack,
    locals,
    //
    result, // status-specific, e.g. returned value or error text
    status,
    //
    sizeof,
}
enum txr_thread_status {
    none,
    running,
    finished,
    error,
    yield,
}

#define txr_thread_destroy
var th/*:txr_thread*/ = argument0;
if (th[txr_thread.actions] != undefined) {
    ds_stack_destroy(th[txr_thread.stack]);
    ds_stack_destroy(th[txr_thread.jumpstack]);
    ds_map_destroy(th[txr_thread.locals]);
    th[@txr_thread.actions] = undefined;
    th[@txr_thread.status] = txr_thread_status.none;
}

#define txr_thread_read
/// @param buffer
/// @return thread
var b/*:Buffer*/ = argument0;
var th/*:txr_thread*/ = array_create(txr_thread.sizeof);
th[@txr_thread.status] = buffer_read(b, buffer_u8);
th[@txr_thread.pos] = buffer_read(b, buffer_s32);
th[@txr_thread.result] = txr_value_read(b);
//show_debug_message(txr_sfmt("stack@%", b.tell()));
var s = ds_stack_create();
repeat (buffer_read(b, buffer_u32)) ds_stack_push(s, txr_value_read(b));
th[@txr_thread.stack] = s;
//
s = ds_stack_create();
repeat (buffer_read(b, buffer_u32)) ds_stack_push(s, buffer_read(b, buffer_s32));
th[@txr_thread.stack] = s;
//show_debug_message(txr_sfmt("locals@%", b.tell()));
var m = ds_map_create();
n = buffer_read(b, buffer_u32);
repeat (n) {
    var v = txr_value_read(b);
    m[?v] = txr_value_read(b);
}
th[@txr_thread.locals] = m;
//show_debug_message(txr_sfmt("actions@%", b.tell()));
var n = buffer_read(b, buffer_u32);
var w = array_create(n);
for (var i = 0; i < n; i++) {
    w[i] = txr_action_read(b);
}
th[@txr_thread.actions] = w;
//
return th;

#define txr_thread_resume
/// @param txr_thread
/// @param ?yield_value - only used if resuming a thread after a yield
/// @return txr_thread_status
var th/*:txr_thread*/ = argument[0];
var val = undefined;
if (argument_count > 1) val = argument[1];
var arr = th[txr_thread.actions];
if (arr == undefined) exit;
var _previous = txr_thread_current;
txr_thread_current = th;
var stack/*:Stack*/ = th[txr_thread.stack];
switch (th[txr_thread.status]) {
    case txr_thread_status.error:
    case txr_thread_status.finished:
        return th[txr_thread.status];
    case txr_thread_status.yield:
        ds_stack_push(stack, val);
        break;
}
th[@txr_thread.result] = val;
var pos = th[txr_thread.pos];
var len = array_length_1d(arr);
var locals = th[txr_thread.locals];
var q = undefined;
var halt = undefined;
th[@txr_thread.status] = txr_thread_status.running;
while (pos < len) {
    if (halt != undefined) break;
    q = arr[pos++];
    switch (q[0]) {
        case txr_action.number: ds_stack_push(stack, q[2]); break;
        case txr_action._string: ds_stack_push(stack, q[2]); break;
        case txr_action.unop:
            var v = ds_stack_pop(stack);
            if (q[2] == txr_unop.invert) {
                if (v) ds_stack_push(stack, false);
                else ds_stack_push(stack, true);
            } else if (is_string(v)) {
                halt = "Can't apply unary - to a string";
                continue;
            } else ds_stack_push(stack, -v);
            break;
        case txr_action.binop:
            var b = ds_stack_pop(stack);
            var a = ds_stack_pop(stack);
            if (q[2] == txr_op.eq) {
                a = (a == b);
            }
            else if (q[2] == txr_op.ne) {
                a = (a != b);
            }
            else if (is_string(a) || is_string(b)) {
                if (q[2] == txr_op.add) {
                    if (!is_string(a)) a = string(a);
                    if (!is_string(b)) b = string(b);
                    a += b;
                } else {
                    halt = txr_sfmt("Can't apply % to `%`[%] and `%`[%]",
                        global.txr_op_names[q[2]], a, typeof(a), b, typeof(b));
                    continue;
                }
            }
            else if (txr_is_number(a) && txr_is_number(b)) switch (q[2]) {
                case txr_op.add: a += b; break;
                case txr_op.sub: a -= b; break;
                case txr_op.mul: a *= b; break;
                case txr_op.fdiv: a /= b; break;
                case txr_op.fmod: if (b != 0) a %= b; else a = 0; break;
                case txr_op.idiv: if (b != 0) a = a div b; else a = 0; break;
                case txr_op.shl: a = (a << b); break;
                case txr_op.shr: a = (a >> b); break;
                case txr_op.iand: a &= b; break;
                case txr_op.ior: a |= b; break;
                case txr_op.ixor: a ^= b; break;
                case txr_op.lt: a = (a < b); break;
                case txr_op.le: a = (a <= b); break;
                case txr_op.gt: a = (a > b); break;
                case txr_op.ge: a = (a >= b); break;
                default:
                    halt = txr_sfmt("Can't apply %", global.txr_op_names[q[2]]);
                    continue;
            } else {
                halt = txr_sfmt("Can't apply % to `%`[%] and `%`[%]",
                    global.txr_op_names[q[2]], a, typeof(a), b, typeof(b));
                continue;
            }
            ds_stack_push(stack, a);
            break;
        case txr_action.ident:
            var v = variable_instance_get(id, q[2]);
            ds_stack_push(stack, v);
            break;
        case txr_action.set_ident:
            variable_instance_set(id, q[2], ds_stack_pop(stack));
            break;
        case txr_action.get_local:
            ds_stack_push(stack, locals[?q[2]]);
            break;
        case txr_action.set_local:
            locals[?q[2]] = ds_stack_pop(stack);
            break;
        case txr_action.call:
            var args = global.txr_exec_args;
            ds_list_clear(args);
            var i = q[3], v;
            while (--i >= 0) args[|i] = ds_stack_pop(stack);
            txr_function_error = undefined;
            switch (q[3]) {
                case 0: v = script_execute(q[2]); break;
                case 1: v = script_execute(q[2], args[|0]); break;
                case 2: v = script_execute(q[2], args[|0], args[|1]); break;
                case 3: v = script_execute(q[2], args[|0], args[|1], args[|2]); break;
                case 4: v = script_execute(q[2], args[|0], args[|1], args[|2], args[|3]); break;
                case 5: v = script_execute(q[2], args[|0], args[|1], args[|2], args[|3], args[|4]); break;
                case 6: v = script_execute(q[2], args[|0], args[|1], args[|2], args[|3], args[|4], args[|5]); break;
                case 7: v = script_execute(q[2], args[|0], args[|1], args[|2], args[|3], args[|4], args[|5],args[|6]); break;
                case 8: v = script_execute(q[2], args[|0], args[|1], args[|2], args[|3], args[|4], args[|5],args[|6],args[|7]); break;
                case 9: v = script_execute(q[2], args[|0], args[|1], args[|2], args[|3], args[|4], args[|5],args[|6],args[|7], args[|9]); break;
                case 10: v = script_execute(q[2], args[|0], args[|1], args[|2], args[|3], args[|4], args[|5],args[|6],args[|7], args[|9], args[|10]); break;
                case 11: v = script_execute(q[2], args[|0], args[|1], args[|2], args[|3], args[|4], args[|5],args[|6],args[|7], args[|9], args[|10], args[|11]); break;
                case 12: v = script_execute(q[2], args[|0], args[|1], args[|2], args[|3], args[|4], args[|5],args[|6],args[|7], args[|9], args[|10], args[|11], args[|12]); break;
                case 13: v = script_execute(q[2], args[|0], args[|1], args[|2], args[|3], args[|4], args[|5],args[|6],args[|7], args[|9], args[|10], args[|11], args[|12], args[|13]); break;
                // and so on
                default:
                    halt = txr_sfmt("Too many arguments (%)", q[3]);
                    continue;
            }
            // hit an error?:
            halt = txr_function_error;
            if (halt != undefined) continue;
            // thread yielded/destroyed?:
            if (th[txr_thread.status] != txr_thread_status.running) {
                halt = th[txr_thread.status];
                continue;
            }
            ds_stack_push(stack, v);
            break;
        case txr_action.ret: pos = len; break;
        case txr_action.discard: ds_stack_pop(stack); break;
        case txr_action.jump: pos = q[2]; break;
        case txr_action.jump_unless:
            if (ds_stack_pop(stack)) {
                // OK!
            } else pos = q[2];
            break;
        case txr_action.jump_if:
            if (ds_stack_pop(stack)) pos = q[2];
            break;
        case txr_action.band:
            if (ds_stack_top(stack)) {
                ds_stack_pop(stack);
            } else pos = q[2];
            break;
        case txr_action.bor:
            if (ds_stack_top(stack)) {
                pos = q[2];
            } else ds_stack_pop(stack);
            break;
        case txr_action.jump_push:
            ds_stack_push(th[txr_thread.jumpstack], pos);
            pos = q[2];
            break;
        case txr_action.jump_pop:
            pos = ds_stack_pop(th[txr_thread.jumpstack]);
            break;
        case txr_action._select:
            var v = ds_stack_pop(stack);
            var posx = q[2];
            if (txr_is_number(v) && v >= 0 && v < array_length_1d(posx)) {
                pos = posx[v];
            } else pos = q[3];
            break;
        default:
            halt = txr_sfmt("Can't run action ID %", q[0]);
            continue;
    }
}
if (halt == undefined) {
    th[@txr_thread.status] = txr_thread_status.finished;
    if (ds_stack_empty(stack)) {
        th[@txr_thread.result] = 0;
    } else th[@txr_thread.result] = ds_stack_pop(stack);
} else if (is_string(halt)) {
    th[@txr_thread.status] = txr_thread_status.error;
    th[@txr_thread.result] = halt + " at " + txr_print_pos(q[1]);
}
th[@txr_thread.pos] = pos;
txr_thread_current = _previous;
return th[txr_thread.status];

#define txr_thread_write
/// @param txr_thread
/// @param buffer
var th/*:txr_thread*/ = argument0, b/*:Buffer*/ = argument1;
//
buffer_write(b, buffer_u8, th[txr_thread.status]);
buffer_write(b, buffer_s32, th[txr_thread.pos]);
txr_value_write(th[txr_thread.result], b);
//show_debug_message(txr_sfmt("stack@%", b.tell()));
var s = th[txr_thread.stack];
var n = ds_stack_size(s), i;
var w = array_create(n), v;
buffer_write(b, buffer_u32, n);
for (i = 0; i < n; i++) w[i] = ds_stack_pop(s);
while (--i >= 0) {
    v = w[i];
    txr_value_write(v, b);
    ds_stack_push(s, v);
}
//
s = th[txr_thread.jumpstack];
n = ds_stack_size(s);
w = array_create(n);
buffer_write(b, buffer_u32, n);
for (i = 0; i < n; i++) w[i] = ds_stack_pop(s);
while (--i >= 0) {
    v = w[i];
    buffer_write(b, buffer_s32, v);
    ds_stack_push(s, v);
}
//show_debug_message(txr_sfmt("locals@%", b.tell()));
var m = th[txr_thread.locals];
n = ds_map_size(m);
buffer_write(b, buffer_u32, n);
v = ds_map_find_first(m);
repeat (n) {
    txr_value_write(v, b);
    txr_value_write(m[?v], b);
    v = ds_map_find_next(m, v);
}
//show_debug_message(txr_sfmt("actions@%", b.tell()));
w = th[txr_thread.actions];
n = array_length_1d(w);
buffer_write(b, buffer_u32, n);
for (i = 0; i < n; i++) {
    txr_action_write(w[i], b);
}

#define txr_thread_yield
/// Causes the currently executing thread to yield,
/// suspending it's execution. The thread can later
/// be resumed by calling txr_thread_resume(th, result)
/// and `result` will be returned to the resuming code.
/// See https://en.wikipedia.org/wiki/Coroutine
var th/*:txr_thread*/ = txr_thread_current;
if (th != undefined) {
    th[@txr_thread.status] = txr_thread_status.yield;
    return th;
} else return undefined;

#define txr_throw
/// @desc txr_throw(error_text, position)
/// @param error_text
/// @param position
txr_error = argument0 + " at " + string(argument1);
return true;

#define txr_throw_at
/// @param error_text
/// @param token
var tk = argument1;
if (tk[0] == txr_token.eof) {
    return txr_throw(argument0, "<EOF>");
} else return txr_throw(argument0, txr_print_pos(tk[1]));

#define txr_value_read
/// @param buffer
var b/*:Buffer*/ = argument0;
switch (buffer_read(b, buffer_u8)) {
    case 1: return buffer_read(b, buffer_f64);
    case 2: return buffer_read(b, buffer_u64);
    case 3: return buffer_read(b, buffer_s32);
    case 4: return buffer_read(b, buffer_bool);
    case 5: return buffer_read(b, buffer_string);
    case 6:
        var n = buffer_read(b, buffer_u32);
        var r = array_create(n);
        for (var i = 0; i < n; i++) {
            r[i] = txr_value_read(b);
        }
        return r;
    default: return undefined;
}

#define txr_value_write
/// @param value
/// @param buffer
var v = argument0, b/*:Buffer*/ = argument1;
if (is_real(v)) {
    buffer_write(b, buffer_u8, 1);
    buffer_write(b, buffer_f64, v);
} else if (is_int64(v)) {
    buffer_write(b, buffer_u8, 2);
    buffer_write(b, buffer_u64, v);
} else if (is_int32(v)) {
    buffer_write(b, buffer_u8, 3);
    buffer_write(b, buffer_s32, v);
} else if (is_bool(v)) {
    buffer_write(b, buffer_u8, 4);
    buffer_write(b, buffer_bool, v);
} else if (is_string(v)) {
    buffer_write(b, buffer_u8, 5);
    buffer_write(b, buffer_string, v);
} else if (is_array(v)) {
    buffer_write(b, buffer_u8, 6);
    var n = array_length_1d(v);
    buffer_write(b, buffer_u32, n);
    for (var i = 0; i < n; i++) {
        txr_value_write(v[i], b);
    }
} else {
    buffer_write(b, buffer_u8, 0);
}

#define txr_a
/// txr_a(val1, val2, val3, ...)
var numElems = argument_count;

//if(numElems == 0) numElems = 100;

var arr = array_create(numElems);
show_debug_message("Made an array with " + string(numElems + 1) + " elements. " + string(is_array(arr)));

var i = 0;
for(i = 0; i < argument_count; i++)
    arr[i] = argument[i];

return arr;

