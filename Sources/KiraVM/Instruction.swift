import Foundation

public enum Instruction: UInt8, Sendable {
    // Stack manipulation
    case push_int = 0x01       // operand: UInt16 (index into integer pool)
    case push_float = 0x02     // operand: UInt16 (index into float pool)
    case push_string = 0x03    // operand: UInt16 (index into string table)
    case push_bool_true = 0x04
    case push_bool_false = 0x05
    case push_nil = 0x06
    case pop = 0x07
    case dup = 0x08
    case swap = 0x09

    // Locals
    case load_local = 0x10     // operand: UInt8
    case store_local = 0x11    // operand: UInt8

    // Globals
    case load_global = 0x12    // operand: UInt16
    case store_global = 0x13   // operand: UInt16

    // Object field access
    case load_field = 0x14     // operand: UInt16
    case store_field = 0x15    // operand: UInt16

    // Array access
    case load_index = 0x16
    case store_index = 0x17

    // Integer arithmetic
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

    // Float arithmetic
    case add_float = 0x30
    case sub_float = 0x31
    case mul_float = 0x32
    case div_float = 0x33
    case neg_float = 0x34

    // Type conversions
    case int_to_float = 0x40
    case float_to_int = 0x41

    // Comparison
    case eq_int = 0x50, neq_int = 0x51, lt_int = 0x52, gt_int = 0x53, lte_int = 0x54, gte_int = 0x55
    case eq_float = 0x56, lt_float = 0x57, gt_float = 0x58
    case eq_ref = 0x59

    // Logic
    case and_bool = 0x60
    case or_bool = 0x61
    case not_bool = 0x62

    // Control flow
    case jump = 0x70           // operand: Int16 (relative byte offset)
    case jump_if_true = 0x71   // operand: Int16
    case jump_if_false = 0x72  // operand: Int16
    case jump_if_nil = 0x73    // operand: Int16

    // Function calls
    case call = 0x80           // operand: UInt8 argCount (callee under args)
    case call_native = 0x81    // operand: UInt16 native index
    case tail_call = 0x82      // operand: UInt8 argCount
    case ret = 0x83

    // Object creation
    case new_object = 0x90     // operand: UInt16 type descriptor index
    case new_array = 0x91
    case array_length = 0x92
    case array_append = 0x93
    case array_slice = 0x94

    // String operations
    case string_concat = 0xA0
    case string_length = 0xA1
    case string_interpolate = 0xA2 // operand: UInt8 segment count
    case print = 0xA3
    case make_color = 0xA4

    // Closures
    case make_closure = 0xB0   // operand: UInt16 function index, then UInt8 captureCount, then capture local slots
    case load_capture = 0xB1   // operand: UInt8 capture slot

    // FFI
    case ffi_call = 0xC0
    case ffi_load = 0xC1

    // Coroutines / fibers
    case fiber_new = 0xD0      // operand: UInt16 function index
    case fiber_resume = 0xD1
    case yield = 0xD2

    // Optional chaining
    case unwrap_or_jump = 0xE0 // operand: Int16

    // Debug
    case breakpoint = 0xF0
    case line_number = 0xF1    // operand: UInt16
}
