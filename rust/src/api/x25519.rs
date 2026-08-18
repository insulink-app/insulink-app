//! X25519 for the Omnipod DASH pairing handshake.
//!
//! Pairing derives the pod's long-term key from an ephemeral X25519 exchange:
//! controller and pod each send a public key plus a nonce, and the shared
//! secret feeds the AES-CMAC ladder in `key_exchange.dart` that produces the
//! LTK and the two confirmation values.
//!
//! Only the curve operation lives here — the ladder itself is Dart, where the
//! known-answer tests can cover it. Dart has no X25519 (PointyCastle ships
//! CMAC and CCM but not Curve25519), and hand-rolling a Montgomery ladder for
//! a key that authorises insulin delivery is not a trade worth making, so the
//! audited `x25519-dalek` does it.
//!
//! Reference: AndroidAPS `X25519KeyGenerator.kt` / `KeyExchange.kt` (AGPL-3.0).

use rand_core::RngCore;
use x25519_dalek::{PublicKey, StaticSecret};

/// Generates a fresh 32-byte X25519 private key from the OS entropy source.
///
/// A pairing key is only ever used for one pod activation; reusing one across
/// pods would let a recovered key unlock a second pod's session.
#[flutter_rust_bridge::frb(sync)]
pub fn x25519_generate_private_key() -> Vec<u8> {
    let mut seed = [0u8; 32];
    rand_core::OsRng.fill_bytes(&mut seed);
    StaticSecret::from(seed).to_bytes().to_vec()
}

/// Derives the matching public key for a private key.
#[flutter_rust_bridge::frb(sync)]
pub fn x25519_public_from_private(private_key: Vec<u8>) -> Result<Vec<u8>, String> {
    let secret = parse_secret(private_key)?;
    Ok(PublicKey::from(&secret).to_bytes().to_vec())
}

/// Computes the shared secret between our private key and the pod's public key.
///
/// An all-zero result means the peer sent a low-order point, which forces a
/// known shared secret regardless of our key. That is rejected rather than
/// returned, so a spoofed pod cannot steer the pairing onto a key it chose.
#[flutter_rust_bridge::frb(sync)]
pub fn x25519_shared_secret(
    private_key: Vec<u8>,
    peer_public_key: Vec<u8>,
) -> Result<Vec<u8>, String> {
    let secret = parse_secret(private_key)?;
    let peer: [u8; 32] = peer_public_key
        .try_into()
        .map_err(|_| "peer public key must be 32 bytes".to_string())?;
    let shared = secret.diffie_hellman(&PublicKey::from(peer));
    if !shared.was_contributory() {
        return Err("peer sent a low-order public key".to_string());
    }
    Ok(shared.to_bytes().to_vec())
}

fn parse_secret(private_key: Vec<u8>) -> Result<StaticSecret, String> {
    let bytes: [u8; 32] = private_key
        .try_into()
        .map_err(|_| "private key must be 32 bytes".to_string())?;
    Ok(StaticSecret::from(bytes))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// RFC 7748 section 6.1 test vector, so a broken dependency swap is caught
    /// here rather than during a pod pairing.
    #[test]
    fn rfc7748_shared_secret() {
        let alice_private =
            hex("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a");
        let bob_private =
            hex("5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb");
        let alice_public = x25519_public_from_private(alice_private.clone()).unwrap();
        let bob_public = x25519_public_from_private(bob_private.clone()).unwrap();
        assert_eq!(
            hex_string(&alice_public),
            "8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a"
        );
        assert_eq!(
            hex_string(&bob_public),
            "de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f"
        );
        let shared = x25519_shared_secret(alice_private, bob_public).unwrap();
        assert_eq!(
            hex_string(&shared),
            "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742"
        );
        assert_eq!(
            shared,
            x25519_shared_secret(bob_private, alice_public).unwrap()
        );
    }

    #[test]
    fn rejects_low_order_peer_key() {
        let private = x25519_generate_private_key();
        let low_order = vec![0u8; 32];
        assert!(x25519_shared_secret(private, low_order).is_err());
    }

    #[test]
    fn rejects_wrong_length_keys() {
        assert!(x25519_public_from_private(vec![0u8; 31]).is_err());
        assert!(x25519_shared_secret(vec![0u8; 32], vec![0u8; 33]).is_err());
    }

    fn hex(text: &str) -> Vec<u8> {
        (0..text.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&text[i..i + 2], 16).unwrap())
            .collect()
    }

    fn hex_string(bytes: &[u8]) -> String {
        bytes.iter().map(|b| format!("{:02x}", b)).collect()
    }
}
