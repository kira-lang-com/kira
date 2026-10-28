# Foundation: net

Networking services and cryptography. QUIC is in `quic/`, TLS in `tls/`.

Every file below is part of the Foundation module; folders group files only.

## Public types and macros

- `enum CipherSuite`
- `enum CryptoFailure`
- `enum HashAlgorithm`
- `enum KeyGroup`
- `enum NetFailure`
- `enum NetInterest`
- `enum SignatureScheme`
- `struct Accepted`
- `struct AeadKey`
- `struct ChainCheck`
- `struct Datagram`
- `struct KeyAgreement`
- `struct Lookup`
- `struct NetEvent`
- `struct Poller`
- `struct SigningKey`
- `struct TcpListener`
- `struct TcpStream`
- `struct UdpSocket`

## Files

- CryptoServices.kira
- NetServices.kira
- quic/Acks.kira
- quic/Congestion.kira
- quic/Connection.kira
- quic/ConnectionReceive.kira
- quic/ConnectionSend.kira
- quic/ConnectionSetup.kira
- quic/ConnectionStreams.kira
- quic/Endpoint.kira
- quic/EndpointPackets.kira
- quic/FrameEncoding.kira
- quic/Frames.kira
- quic/LossRecovery.kira
- quic/Node.kira
- quic/Packets.kira
- quic/QuicCodes.kira
- quic/Recovery.kira
- quic/Retry.kira
- quic/Streams.kira
- quic/TestPki.kira
- quic/TransportParameters.kira
- tls/Authentication.kira
- tls/ClientFlow.kira
- tls/Handshake.kira
- tls/KeySchedule.kira
- tls/Messages.kira
- tls/Records.kira
- tls/ServerFlow.kira
- tls/TlsCodes.kira
- tls/TlsStream.kira
