# Foundation: formats

JSON values, parsing and writing; DEFLATE and zlib; PNG and JPEG decoding; the klist document reader; and the Ksl shader artifact.

Every file below is part of the Foundation module; folders group files only.

## Public types and macros

- `class Inflater`
- `class JpegDecoder`
- `class KlistParser`
- `class PngDecoder`
- `enum ImageFailure`
- `enum InflateFailure`
- `enum JsonFailure`
- `enum JsonLayout`
- `enum JsonStart`
- `enum JsonValue`
- `struct HuffmanCode`
- `struct Image`
- `struct JpegComponent`
- `struct JsonError`
- `struct JsonMember`
- `struct JsonNumberLiteral`
- `struct JsonReader`
- `struct KlistDocument`
- `struct KlistNode`
- `struct KslArtifact`

## Files

- CompressionHuffmanCode.kira
- CompressionInflate.kira
- ImageImage.kira
- ImageJpeg.kira
- ImageJpegPixels.kira
- ImageJpegScan.kira
- ImagePng.kira
- ImagePngPixels.kira
- JsonParse.kira
- JsonValue.kira
- JsonWrite.kira
- Klist.kira
- Ksl.kira
