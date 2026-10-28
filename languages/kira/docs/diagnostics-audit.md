# Diagnostics audit

The inventory of every diagnostic klf-kira reports, classified against the
standards in `diagnostics.md` ("Standards"). It covers the 295 Kira
`DiagnosticSpec` entries in `definitions/language.klfd` and the framework
messages the Kira stages raise (`klf-defsvc`, `klf-driver`, `klf-cli`,
`klf-services`). The classifier is `tools/audit-diagnostics.py`; it reads
the spec table and the `report(.Case, span)` sites in `definitions/`, so its
numbers are a heuristic, and the examples below were checked by reading the
code paths.

## Method

- **Symbol.** A spec is *named at the span* when its report sites pass a name
  or identifier span: the renderer now quotes that identifier in the headline.
  It is *static title names it* when its title quotes a symbol itself. It is
  *missing symbol name* otherwise: the message never says which name was
  wrong, because `klf.diag` records carry only a code and a byte range.
- **Help.** An explanation that says what to write, use, add, declare or
  import is *explanation says what to do*; the rest are *missing help/fix*.
- **Site.** A code the Kira definitions never raise (not in
  `diagnostic-registry.json`, or with no reference outside the tables) is
  listed as unreachable from Kira. Eleven codes are not in the registry at all
  (5013, 5014, 5031, 5032, 5033, 5036, 4044, 3401, 3407, 3408 and one more)
  and six are referenced nowhere; they are raised by framework code or are
  dead.

## Counts

| Class | Before | After (renderer change) |
| --- | ---: | ---: |
| Specs | 295 | 295. The logging work's `LogCategoryPath` reused 2097, which `ComputedSetterOnLet` holds; it moved to 2105 (uncommitted, in its language.klfd hunk and registry row) |
| Named at the span (identifier quoted in the headline) | 0 quoted | 73 quote their identifier |
| Static title names the symbol | 35 | 35 |
| Missing symbol name | 187 | 187 (needs the Kira side to pass the name; see "Remaining") |
| Explanation says what to do | 148 | 148 |
| Missing help / fix | 147 | 138 (21 specs carry a `help` line since the help plumbing; needs the Kira side to compute did-you-mean and import hints) |
| Framework conflict messages (9002 function, type, global) | mangled names, no units, no places | source names, unit labels, both declaration places, what differs |
| Framework messages that name their symbol | the merge conflicts named mangled internal names | the merge conflicts name the source symbol; the renderer quotes identifiers |

The 73 named-span codes, by number: 3003 3004 3005 3007 3010 3012 3020 3023
3033 3050 3051 3052 3059 3060 3061 3062 3091 3092 3093 3107 3120 3128 3130
3157 3174 3175 3181 3182 3184 3186 3187 3200 3205 3234 3255 3274 3276 3278
3285 3286 3288 3289 3290 3293 3294 3298 3299 3301 3308 3309 3310 3315 3317
3337 3345 3346 3353 3368 3369 3372 3374 3376 3382 3383 3393 3394 3395 3399
3402 3403 3406 6002 9001.

## Before and after, for the cryptic messages named in the task

| Message (before) | After |
| --- | --- |
| `defines `ambientStateViewLogCount` in more than one unit` with `unit definition defines it at ...` twice | The headline names the source name; each unit is named (`` `unit` `` or `(unnamed unit)`); the note says what differs. The unit-merge logic itself is owned by the conformers work (see Remaining). |
| `declares ApprovalGate_G1876825535242 differently in two units` | `declares `ApprovalGate` differently in two units`, with where each declaration is written and the first part that differs (kind, fields, or cases listed by name). |
| `duplicate definition textOf$Array<UN8>#Network lowered in two units` | This text is not in the current tree; the framework's duplicate-definition message is the function conflict above, which now renders `textOf<Array<UN8>>`. |
| `KLF-KIR-9002` globals: `defines global ...` | Source name (instance number and `#` stripped). |
| `error[4036] native declarations unreadable` | Unchanged text: the label already says what a `klffi` names. The path is not carried (see Remaining). |
| `error[4020] dependency has no readable manifest` | Unchanged; the label names the expected `package.kira`. |
| `error[3050] unknown type`, `3061 call to an undefined function`, `3060 undefined name` | The identifier under the span is quoted: ``call to an undefined function `missingThing` ``. |
| `3092`, `3183`, `3003` in generated bindings | Identifier quoted when the span is one. Generated-origin tracing is not in the excerpt yet (see Remaining). |

## Worst offenders

1. **Missing symbol name (187 specs).** The `klf.diag` record carries a code
   and a byte range, so type errors such as `3183 argument type mismatch`
   cannot say which argument or which types. Fix: a diagnostic record with a
   subject text, passed from the Kira report sites (`klfsvc_diag_error_text`
   or a `subject` field on `RuntimeDiagnostic`).
2. **Missing help (138 specs; 21 now have a help line).** Most `explanation`s state the rule but not the
   fix. The fix needs symbol lookup (did-you-mean over the declared names;
   the import that declares the name); this is the Kira side.
3. **Framework conflicts without places.** The merge errors in `drive.rs`
   and `unit_conflict.rs` named mangled names and gave no declaration
   locations for types. Now fixed in rendering; the unit names come from
   `Module.name`, which is empty for some units (rendered as `(unnamed unit)`).
4. **Traps (`KLF-RT-*`).** The runtime's trap codes print a code and a
   message; the source location is shown when the trap carries a span
   (`source_spans.rs`, `trap_message`). A trap without a span still prints an
   opaque code. Not changed here.
5. **Dead or unreachable codes (17).** Listed above; they should be removed or
   wired.

## Corpus coverage

The corpus `diagnostics` comparison checks `<code>:<line>` pairs
(`klf-driver/src/corpus/mod.rs`). It does not check the rendered text, so a
regression in headline, label, note or help is invisible to it. The renderer
has golden tests in `klf-services/src/snippet.rs`; a corpus comparison of the
full text is listed under Remaining.

## Remaining

- The Kira report sites carry no subject text (worst offender 1). This is the
  largest class and the largest change: `report(...)` in
  `definitions/semantics/*.klfd` must pass the name, and `klf-native-rt`,
  `services.rs` and the VM bridge must carry it into `RuntimeDiagnostic`.
- Generated-origin tracing is not in the rendered excerpt; `location.rs`
  already maps a generated line to its origin for the header, so the excerpt
  should follow the same mapping.
- `4036` and `4020` do not carry the path of the file they failed to read.
- A corpus comparison of full rendered text (a `rendered` compare in
  `klf-driver/src/corpus`).
- The framework changes need an Edmond build to ship; they type-check here.
