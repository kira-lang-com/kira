# Foundation: tls

TLS 1.3 handshake, key schedule, records and streams, and the TLS registry codes (`TlsCodes.kira`).

Every file below is part of the Foundation module; folders group files only.

## Public types and macros

- `enum TlsAlert`
- `enum TlsCarrier`
- `enum TlsContentType`
- `enum TlsEncryptionLevel`
- `enum TlsEvent`
- `enum TlsExtensionType`
- `enum TlsHandshakeStage`
- `enum TlsHandshakeType`
- `enum TlsKeyLabels`
- `enum TlsRole`
- `enum TlsSigner`
- `enum TlsStreamState`
- `struct TlsAgreement`
- `struct TlsCertificateChain`
- `struct TlsCertificateProof`
- `struct TlsClientHello`
- `struct TlsClientSettings`
- `struct TlsExtension`
- `struct TlsHandshake`
- `struct TlsHandshakeMessage`
- `struct TlsHelloChoice`
- `struct TlsInnerRecord`
- `struct TlsKeyShare`
- `struct TlsLevelBytes`
- `struct TlsLevelSecrets`
- `struct TlsMessageBuffer`
- `struct TlsRecordFrame`
- `struct TlsRecordKeys`
- `struct TlsServerHello`
- `struct TlsServerIdentity`
- `struct TlsServerSettings`
- `struct TlsShareOffer`
- `struct TlsStageKeys`
- `struct TlsStream`
- `struct TlsSuiteParameters`
- `struct TlsTrafficKeys`
- `struct TlsTranscript`

## Files

- Authentication.kira
- ClientFlow.kira
- Handshake.kira
- KeySchedule.kira
- Messages.kira
- Records.kira
- ServerFlow.kira
- TlsCodes.kira
- TlsStream.kira
