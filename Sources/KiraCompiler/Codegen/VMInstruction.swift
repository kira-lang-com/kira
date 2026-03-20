import Foundation

// Mirrors `KiraVM.Instruction` for bytecode emission.
public enum Instruction: UInt8, Sendable {
    case push_int = 0x01
    case push_float = 0x02
    case push_string = 0x03
    case push_bool_true = 0x04
    case push_bool_false = 0x05
    case push_nil = 0x06
    case pop = 0x07
    case dup = 0x08
    case swap = 0x09

    case load_local = 0x10
    case store_local = 0x11

    case load_global = 0x12
    case store_global = 0x13

    case load_field = 0x14
    case store_field = 0x15

    case load_index = 0x16
    case store_index = 0x17

    case add_int = 0x20
    case sub_int = 0x21
    case mul_int = 0x22
    case div_int = 0x23
    case mod_int = 0x24
    case neg_int = 0x25
    case bitand_int = 0x26
    case bitor_int = 0x27
    case bitxor_int = 0x28
    case shl_int = 0x29
    case shr_int = 0x2A

    case add_float = 0x30
    case sub_float = 0x31
    case mul_float = 0x32
    case div_float = 0x33
    case neg_float = 0x34

    case int_to_float = 0x40
    case float_to_int = 0x41

    case eq_int = 0x50
    case neq_int = 0x51
    case lt_int = 0x52
    case gt_int = 0x53
    case lte_int = 0x54
    case gte_int = 0x55
    case eq_float = 0x56
    case lt_float = 0x57
    case gt_float = 0x58
    case eq_ref = 0x59

    case and_bool = 0x60
    case or_bool = 0x61
    case not_bool = 0x62

    case jump = 0x70
    case jump_if_true = 0x71
    case jump_if_false = 0x72
    case jump_if_nil = 0x73

    case call = 0x80
    case call_native = 0x81
    case tail_call = 0x82
    case ret = 0x83
    case call_protocol_method = 0x84

    case new_object = 0x90
    case new_array = 0x91
    case array_length = 0x92
    case array_append = 0x93
    case array_slice = 0x94
    case make_ffi_array = 0x95
    case new_typed_object = 0x96

    case string_concat = 0xA0
    case string_length = 0xA1
    case string_interpolate = 0xA2
    case print = 0xA3
    case make_color = 0xA4

    case make_closure = 0xB0
    case load_capture = 0xB1

    case ffi_call = 0xC0
    case ffi_load = 0xC1
    case ffi_callback0 = 0xC2
    case ffi_callback1_i32 = 0xC3

    case fiber_new = 0xD0
    case fiber_resume = 0xD1
    case yield = 0xD2

    case unwrap_or_jump = 0xE0

    case breakpoint = 0xF0
    case line_number = 0xF1
}
