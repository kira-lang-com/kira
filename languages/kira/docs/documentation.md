# Documentation comments

Kira has two kinds of comment, and each says one thing:

- `//` says why. It explains a decision, a constraint or a non-obvious
  consequence next to the code it concerns. It is read by people working on
  the code, and it is never extracted.
- `///` documents the contract. It describes what a declaration is for, what
  it takes, what it returns and how it fails. It is read by people using the
  declaration, and `kira doc` extracts it.
- `//!` documents the file (a module). It is written at the top of the file,
  before its first token, and describes the module as a whole.

A `///` comment never explains how a body works, and a `//` comment never
restates the signature. Both are plain text to the compiler; only `///` and
`//!` reach the documentation.

## Syntax

A doc comment is one or more consecutive lines beginning with `///` (outer)
or `//!` (inner). Lines with nothing but whitespace between them form one
comment. A line of four or more slashes, `////`, is an ordinary comment, so a
rule drawn across a line stays out of the docs.

```kira
/// Adds the discount to the price.
///
/// The discount is a fraction of the price, so `0.1` takes off a tenth.
/// Returns the price unchanged when the discount is zero.
public function discounted(price: Number, discount: Number) -> Number {
    return price - price * discount
}
```

Inside a doc comment, the text after `///` is the line's content with one
leading space removed. The comment is Markdown (see below).

## Attachment

An outer doc comment documents the declaration whose first token follows it,
with nothing else in between except whitespace and other comments. Annotations
belong to the declaration, so the comment goes above them:

```kira
/// The entry point.
@Main
function main() -> Number { ... }
```

The parser attaches doc comments to:

- top-level functions, structs, classes, enums, constructs, traits, aliases,
  distincts, namespaces, extensions and `let` or `var` globals;
- struct fields and methods, enum cases and methods (each documents its own
  member, and the member's owner is its type).

A doc comment that is not followed by one of these is an error, because it
would document nothing:

- a doc comment inside a function body, before a statement, is error 2101;
- a doc comment after the last declaration of a file is error 2101;
- a doc comment between an annotation and its declaration is error 2101,
  because the declaration's first token is the annotation: write the comment
  above the annotation.

A `//!` comment is claimed by the file when it comes before the file's first
token, which may be an `import`. A `//!` written after that is error 2102.

## Markdown

The text is CommonMark-style Markdown, written the way the Rust standard
library and popular Rust crates write theirs. `kira doc` renders it as written.

- The first line is the summary: one sentence saying what the declaration is.
  It is shown in the index.
- A blank line, then detail paragraphs describing behaviour.
- Sections are `#` headings, in this order when they apply:
  - `# Examples`: one or more fenced code blocks showing a call or a use. Write
    them so they read as runnable Kira.
  - `# Errors`: when the declaration returns a `Result`, each failure case and
    when it is returned.
  - `# Panics`: when the declaration can trap (integer overflow, division by
    zero, an out-of-range index, `runtimeTrap()`), and the condition that traps.
  - `# Safety`: when callers must uphold something the compiler does not check
    (a native pointer, a raw handle, an ownership promise).
  - `# Arguments` and `# Returns`: only where the meaning is not obvious from the
    name and type. `# Arguments` takes one bullet per parameter,
    `` - `name`: what it means ``. `# Returns` says what an absent value stands for.
- Public types document each field and each case, with a `///` comment above it.
- Module and package docs (`//!`) give an overview, a quick-start example, and,
  for a library, its feature list.
- Inline code uses backticks. Name related items in backticks; they are not
  linked.

Doctests: `kira doc --check` compiles each fenced code block under `# Examples`.
Each block is written to a package under `.kira-doctests/` in the documented
package's directory. That package depends on the documented package by its path
and imports it, so an example can name the package's items directly. The block
is run as the body of `@Main function main() -> Number`, unless it declares its
own `@Main`. A line written `# ` (or `#` alone) is hidden in the docs and still
compiled, with the marker removed.

The fence's info string picks what the block is checked for:

- empty, `kira` or `no_run`: must compile (`no_run` is not run, and `kira doc`
  never runs an example);
- `compile_fail`: must not compile;
- `ignore`, or any other language: not checked.

A failing example is error 2107 at its doc comment, with the compiler's errors
under it. A `compile_fail` example that compiles is error 2108. Running examples
is not done yet: `kira test` does not run doctests.

## Intra-doc links

A name written in backticks inside square brackets, `` [`Name`] ``, links to
the item it names. `kira doc` resolves each one:

- `` [`Name`] `` names a top-level declaration of the package, such as a
  struct, function, enum or `let`.
- `` [`Type.member`] `` names a field, method or case of a type of the package.
- `` [`package::Item`] `` names an item of the package whose name is `package`.
  The package's own name is written as the package title, `Links::Unit` above.

A link to an item with a section on the page (an exported declaration, or a
member of an exported type) is rendered as a link to that section, and its
text is shown in code. A link to a declaration that has no section (a private
one) is kept as written. A link inside a fenced code block is code, not a link.
Writing a name in plain backticks, `` `Name` ``, still works and is not linked.

`kira doc --check` reports each link that names no item as error 2106, at the
doc comment holding it. A `did you mean` line under the error gives the nearest
name the package declares when it is a likely typo.

`kira doc --format json` writes each entry's links in a `links` array of
`{"text": "Name", "target": "#anchor"}`: `target` is the section's anchor, `""`
for a link to an item without a section, and `null` for a link that names no
item.

## `kira doc`

```
kira doc            # the package's public API as Markdown, to standard output
kira doc <path>     # the package at <path>
kira doc --check    # error for each public declaration or member without docs
```

`kira doc` checks the package the way `kira check` does, then writes:

1. a `# <package>` title;
2. the `//!` documentation of the package's own module, when it has one;
3. `## Public API`, an index with one bullet per public declaration: its kind,
   its name and its summary (or `No documentation.`);
4. one section per public declaration, `## <kind> <name>`, with its text and a
   `### <member>` section for each public field, method or case of a public
   type.

Only the package's own sources are documented. A library it depends on is
documented by that library's package.

`kira doc --check` writes no Markdown. It reports error 2103 at the name of
each public declaration without a doc comment, and at each field, method or
case of a public type without one, then exits with status 1 when there are
any. A member of a struct is public when the struct is; a member marked
`private` is not checked. A raw enum's generated methods are not checked,
since they are not written in the source.

`kira doc --check` also reports error 2106 at each doc comment holding an
intra-doc link that names no item (see Intra-doc links).

`kira doc --format json` writes the documentation as JSON instead; see the
intra-doc links above for its `links` arrays.

## Diagnostics

| Code | Meaning |
| --- | --- |
| 2101 | A `///` doc comment is not followed by a declaration. |
| 2102 | A `//!` doc comment comes after the file's first token. |
| 2103 | A public declaration or member has no doc comment (`kira doc --check`). |
| 2104 | `kira doc --format` names a format other than `markdown` or `json`. |
| 2106 | An intra-doc link names no item of the package (`kira doc --check`). |
| 2107 | A `# Examples` code block does not compile (`kira doc --check`). |
| 2108 | A `compile_fail` example compiles (`kira doc --check`). |

## Editor

The editor classifies `///` and `//!` as documentation comments
(`classDocComment`), and every other `//` comment as a plain comment. The
classification is recorded by the lexer, so it works in the same parse path
the compiler uses.
