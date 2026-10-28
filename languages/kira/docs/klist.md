# The klist format

A `.klist` file holds a program's settings as typed values, like a property
list. `klist!` reads one while compiling (`subset.md`), so a value lives in one
file instead of being written into the code wherever it is used.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<klist version="1">
<dict>
    <string key="BundleIdentifier">com.example.app</string>
    <number key="BuildNumber">412</number>
    <number key="Mask">0xFF000000</number>
    <number key="Scale">0.75</number>
    <true key="SupportsMultipleWindows"/>
    <date key="BuildDate">2026-10-05T14:30:00Z</date>
    <array key="SupportedPlatforms">
        <string>Tessera</string>
    </array>
    <data key="IconHash">3q2+7w==</data>
</dict>
</klist>
```

## Documents

A document is an optional `<?...?>` declaration, then `<klist version="1">`
around exactly one value. Comments `<!-- ... -->` and white space may stand
between elements.

## Values

| Element | Holds | `klist!` gives |
| --- | --- | --- |
| `<dict>` | keyed values | nothing; name a key inside it |
| `<array>` | unkeyed values | `[String]` when every element is a string or date |
| `<string>` | text | `String` |
| `<number>` | an exact decimal | `Number` |
| `<true/>`, `<false/>` | a boolean | `Bool` |
| `<date>` | `YYYY-MM-DDTHH:MM:SSZ`, UTC | `String` |
| `<data>` | padded base64 | `[U8]` |

Every value directly inside a `<dict>` has a `key` attribute, unique within
that dict. No other value has one. `<true/>` and `<false/>` are always empty,
and a number or date never is.

A number is never an integer or a float: it is a `Number`. It is written as a
decimal, an optional sign, digits, and an optional `.` with more digits, or as
`0x` and at most sixteen hexadecimal digits, the bits of a `U64`. A conversion
gives it a width where one is needed: `U32(klist!("Info.klist", "Mask"))`.

Text escapes `&lt;`, `&gt;`, `&amp;`, `&quot;` and `&apos;`; no other entity
is read.

## Key paths

A key path names a value from the root: dict keys and array indexes,
separated by dots. `DocumentTypes.0.Extension` is the `Extension` key of the
first element of the `DocumentTypes` array.
