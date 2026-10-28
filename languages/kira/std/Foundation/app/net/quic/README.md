# Foundation: quic

QUIC version 1: connections, endpoints, streams, packets, frames, loss recovery and congestion control, and the QUIC registry codes (`QuicCodes.kira`).

Every file below is part of the Foundation module; folders group files only.

## Public types and macros

- `enum QuicConnectionState`
- `enum QuicEvent`
- `enum QuicFailure`
- `enum QuicFrame`
- `enum QuicFrameType`
- `enum QuicLongPacketType`
- `enum QuicNodeEvent`
- `enum QuicPacketDrop`
- `enum QuicResend`
- `enum QuicStreamEnding`
- `enum QuicStreamKind`
- `enum QuicStreamProblem`
- `enum QuicTimerKind`
- `enum QuicTransportError`
- `enum QuicTransportParameterId`
- `struct QuicAckFrame`
- `struct QuicAckOutcome`
- `struct QuicAckRange`
- `struct QuicClientSettings`
- `struct QuicCloseFrame`
- `struct QuicClosed`
- `struct QuicConnection`
- `struct QuicConnectionEnd`
- `struct QuicConnectionIds`
- `struct QuicCryptoFrame`
- `struct QuicDial`
- `struct QuicEndpoint`
- `struct QuicEndpointConnection`
- `struct QuicEndpointSettings`
- `struct QuicIdentity`
- `struct QuicIncomingPacket`
- `struct QuicLevelKeys`
- `struct QuicLimits`
- `struct QuicLossRecovery`
- `struct QuicNewConnectionIdFrame`
- `struct QuicNewReno`
- `struct QuicNode`
- `struct QuicNodeConnection`
- `struct QuicNodeOptions`
- `struct QuicNodeSlot`
- `struct QuicOpened`
- `struct QuicOutgoingPacket`
- `struct QuicPacketDraft`
- `struct QuicPacketHeader`
- `struct QuicPacketShape`
- `struct QuicPacketSpace`
- `struct QuicPhaseSecrets`
- `struct QuicPiece`
- `struct QuicRawHeader`
- `struct QuicReassembly`
- `struct QuicReceivedRanges`
- `struct QuicRecoveryTimer`
- `struct QuicResetStreamFrame`
- `struct QuicRetryRequest`
- `struct QuicRttEstimator`
- `struct QuicSendSide`
- `struct QuicSentPacket`
- `struct QuicServerSettings`
- `struct QuicServerStart`
- `struct QuicStopSendingFrame`
- `struct QuicStream`
- `struct QuicStreamBytes`
- `struct QuicStreamCount`
- `struct QuicStreamCounts`
- `struct QuicStreamCredit`
- `struct QuicStreamEnd`
- `struct QuicStreamFailure`
- `struct QuicStreamFrame`
- `struct QuicStreamId`
- `struct QuicStreamRead`
- `struct QuicTransportParameters`
- `trait QuicCongestionController`

## Files

- Acks.kira
- Congestion.kira
- Connection.kira
- ConnectionReceive.kira
- ConnectionSend.kira
- ConnectionSetup.kira
- ConnectionStreams.kira
- Endpoint.kira
- EndpointPackets.kira
- FrameEncoding.kira
- Frames.kira
- LossRecovery.kira
- Node.kira
- Packets.kira
- QuicCodes.kira
- Recovery.kira
- Retry.kira
- Streams.kira
- TestPki.kira
- TransportParameters.kira
