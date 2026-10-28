# Foundation: diagnostics

Kira's error catalogue (`KiraError`), the trace helpers, and the trail that `log` statements and failures record, with its reports.

Every file below is part of the Foundation module; folders group files only.

## Public types and macros

- `enum KiraError`
- `enum ProgramEnd`
- `enum TrailKind`
- `enum TrailLevel`
- `enum TrailThreshold`
- `struct Trace`
- `struct TrailEvent`
- `struct TrailRule`
- `struct TrailSite`
- `struct TrailState`
- `trait Traced`

## Files

- DiagnosticCodes.kira
- Diagnostics.kira
- Trace.kira
- Trail.kira
- TrailReport.kira
