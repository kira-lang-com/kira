# ksl diagnostics

The kernel carries a diagnostic as one integer, so each KSL family is a
thousands band. The low digits are KSL's own number: `KSLP001` is 1001 and
`KSLS004` is 2004. The titles and explanations are the `DiagnosticSpec` list
in `definitions/language.klfd`.

## Parser (KSLP, 1xxx)

The parser stops at the first error.

| Code | KSL | Meaning |
| --- | --- | --- |
| 1001 | KSLP001 | A token appeared where the grammar allows something else |
| 1002 | KSLP002 | A top-level item is not a declaration |
| 1003 | KSLP003 | A resource is malformed |
| 1004 | KSLP004 | An access mode is not `read`, `read_write` or `write` |
| 1005 | KSLP005 | An annotation is unknown or malformed |
| 1006 | KSLP006 | A stage body holds something a stage cannot contain |
| 1007 | KSLP007 | `threads` does not have three extents |
| 1008 | KSLP008 | An integer literal is larger than the largest `UInt` |

## Semantics (KSLS, 2xxx)

| Code | KSL | Meaning |
| --- | --- | --- |
| 2001 | KSLS001 | A written type names nothing |
| 2002 | KSLS002 | A name is not bound here |
| 2003 | KSLS003 | Two declarations claim one name |
| 2004 | KSLS004 | An expression's type is not the one its position accepts |
| 2005 | KSLS005 | A call has the wrong number of arguments |
| 2006 | KSLS006 | A member does not exist on its type |
| 2007 | KSLS007 | A `@builtin` or `@interpolate` word is unknown, or the stage cannot carry it there |
| 2008 | KSLS008 | Something that cannot be written is assigned |
| 2009 | KSLS009 | A stage lacks its `entry`, has two, or a compute stage's threads or output is wrong |
| 2010 | KSLS010 | An option's default is not a constant of its type |
| 2011 | KSLS011 | An import resolves to no file |
| 2012 | KSLS012 | A resource's type is illegal for its kind |
| 2013 | KSLS013 | More than one shader is declared |
| 2014 | KSLS014 | An operator does not apply to its operands |
| 2015 | KSLS015 | A function can finish without returning its result |
| 2017 | KSLS017 | A `const` or enum variant does not fold to a value of its type |
| 2018 | KSLS018 | Two resources of one group take the same slot |
| 2022 | — | A function reaches itself through its calls (the oracle fails later, in its backends) |
| 2023 | — | A vertex or compute entry reaches `dpdx`, `dpdy` or `fwidth` |

## Kernel keys

The kernel reports what it finds in the lowered module under keys
(`KLF-KSL.md` section 16.4), and the definition maps each key to a code.

| Key | Code |
| --- | --- |
| `shader.uniformity` | 2019 |
| `shader.const-not-finite` | 2017 |
| `shader.const-index` | 2020 |
| `shader.interface-mismatch` | 2009 |
| `shader.override-missing` | 2010 |
| `shader.override-unsupported` | 2021 |
| `shader.target-unsupported` | 2016 |
| `shader.capability` | 2016 |
| `shader.slot-collision` | 2018 |
