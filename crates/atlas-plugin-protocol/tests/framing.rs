use atlas_plugin_protocol::{
    decode_frame, encode_frame, Envelope, FrameError, Hello, MessageKind, MAX_FRAME_BYTES,
};

#[test]
fn round_trips_authenticated_hello() {
    let envelope = Envelope::new(
        "dev.example.clock",
        "menu",
        "instance-1",
        "request-1",
        MessageKind::Hello(Hello {
            nonce: [7; 32],
            package_root: [9; 32],
            min_version: 1,
            max_version: 1,
        }),
    );

    let bytes = encode_frame(&envelope).unwrap();

    assert_eq!(decode_frame(&bytes).unwrap(), envelope);
}

#[test]
fn rejects_oversized_frame() {
    let bytes = vec![0_u8; MAX_FRAME_BYTES + 5];

    assert_eq!(
        decode_frame(&bytes),
        Err(FrameError::FrameTooLarge(MAX_FRAME_BYTES + 1))
    );
}

#[test]
fn rejects_truncated_and_trailing_frames() {
    let envelope = Envelope::new(
        "dev.example.clock",
        "menu",
        "instance-1",
        "request-1",
        MessageKind::Health,
    );
    let mut truncated = encode_frame(&envelope).unwrap();
    truncated.pop();
    assert!(matches!(
        decode_frame(&truncated),
        Err(FrameError::LengthMismatch { .. })
    ));

    let mut trailing = encode_frame(&envelope).unwrap();
    trailing.push(0);
    assert!(matches!(
        decode_frame(&trailing),
        Err(FrameError::LengthMismatch { .. })
    ));
}

#[test]
fn rejects_zero_protocol_version() {
    let mut envelope = Envelope::new(
        "dev.example.clock",
        "menu",
        "instance-1",
        "request-1",
        MessageKind::Health,
    );
    envelope.protocol_version = 0;

    assert_eq!(
        encode_frame(&envelope),
        Err(FrameError::UnsupportedProtocolVersion(0))
    );
}

#[test]
fn rejects_declared_body_above_limit_before_decoding() {
    let declared = u32::try_from(MAX_FRAME_BYTES + 1).unwrap();

    assert_eq!(
        decode_frame(&declared.to_be_bytes()),
        Err(FrameError::FrameTooLarge(MAX_FRAME_BYTES + 1))
    );
}
