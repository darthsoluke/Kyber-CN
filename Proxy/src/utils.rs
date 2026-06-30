// Prepend a 2-byte identifier to the packet
pub fn prepend_identifier(packet: &[u8], identifier: u16) -> Vec<u8> {
    let mut result = Vec::new();
    result.extend_from_slice(&identifier.to_be_bytes()); // Convert identifier to bytes and add to result
    result.extend_from_slice(packet); // Add the original packet
    result
}

// Extract the 2-byte identifier from the packet
pub fn extract_identifier(packet: &[u8]) -> (u16, Vec<u8>) {
    let (id_bytes, packet) = packet.split_at(2);
    let identifier = u16::from_be_bytes([id_bytes[0], id_bytes[1]]); // Convert bytes back to u16
    (identifier, packet.to_vec())
}
