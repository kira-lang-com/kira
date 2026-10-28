# Foundation: derive

The builtin `@Derive` macros written in Kira, and the serialization helpers they share. `DeriveSerde.kira` holds the `Serializable` macro and its wire format; `DeriveSerdeDeserialize.kira` holds the deserializer it calls.

Every file below is part of the Foundation module; folders group files only.

## Public types and macros

- `enum Ordering`
- `macro CaseIterable`
- `macro Clone`
- `macro CustomStringConvertible`
- `macro Equatable`
- `macro Hashable`
- `macro Lerp`
- `macro Ordered`
- `macro Serializable`
- `macro Tagged`

## Files

- Derive.kira
- DeriveCaseIterable.kira
- DeriveCustomStringConvertible.kira
- DeriveHashable.kira
- DeriveLerp.kira
- DeriveOrdered.kira
- DeriveSerde.kira
- DeriveSerdeDeserialize.kira
- DeriveTagged.kira
- SerdeText.kira
