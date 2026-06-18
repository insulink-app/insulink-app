//! EC-JPAKE core for the Dexcom G7 BLE handshake — a faithful Rust port of
//! Juggluco's `ecJPake.cpp` (GPLv3), the only fully-open working implementation.
//!
//! The G7 does NOT use mbedTLS's standard EC-JPAKE wire encoding. It uses a
//! custom framing on secp256r1 (P-256) + SHA-256:
//!   - each round payload is 160 bytes = pubkey1(X32‖Y32) ‖ pubkey2(X32‖Y32) ‖ proof32
//!     (raw affine coords, no 0x04 prefix, no length prefixes)
//!   - the Schnorr ZKP hash input DOES use 4-byte-BE-length ‖ uncompressed-point(65)
//!     per RFC-8235, plus a 6-byte party label.
//!   - session key = SHA256( X(shared_point) )[0:16].
//!
//! Validated in tests against Juggluco's real captured certs and test vectors.
//!
//! Reference (Juggluco, branch `primary`):
//!   Common/src/main/cpp/dexcom/ecJPake.cpp, java.cpp, DexGattCallback.java

use aes::cipher::{BlockEncrypt, KeyInit};
use aes::Aes128;
use p256::elliptic_curve::ops::Reduce;
use p256::elliptic_curve::sec1::{FromEncodedPoint, ToEncodedPoint};
use p256::elliptic_curve::PrimeField;
use p256::{AffinePoint, EncodedPoint, NonZeroScalar, ProjectivePoint, Scalar};
use sha2::{Digest, Sha256};
use std::sync::Mutex;

// Party labels (ecJPake.cpp:333-334). Our proofs use "client"; we validate the
// sensor's proofs with the b label.
const PARTY_A: [u8; 6] = [0x63, 0x6c, 0x69, 0x65, 0x6e, 0x74]; // "client"
const PARTY_B: [u8; 6] = [0x37, 0x56, 0x27, 0x67, 0x56, 0x27];

// Hardcoded round-3 commitment exponent (ecJPake.cpp:489).
const ROUND3_EXPONENT_HEX: &str =
    "fbc971b837e9491e45a4179ed33865c508a1e0a1d350f5af0f96370695fdc393";

// --- helpers ---------------------------------------------------------------

fn scalar_from_be(bytes: &[u8; 32]) -> Scalar {
    // Reduce mod n (matches BN_bin2bn(..) then BN_nnmod(.., order)).
    Scalar::reduce_bytes(bytes.into())
}

fn scalar_from_hex(hex: &str) -> Scalar {
    let mut out = [0u8; 32];
    for i in 0..32 {
        out[i] = u8::from_str_radix(&hex[i * 2..i * 2 + 2], 16).unwrap();
    }
    scalar_from_be(&out)
}

/// Uncompressed SEC1 encoding (0x04 ‖ X ‖ Y, 65 bytes) — `tobytes4`.
fn point_uncompressed(p: &ProjectivePoint) -> [u8; 65] {
    let enc = p.to_affine().to_encoded_point(false);
    let mut out = [0u8; 65];
    out.copy_from_slice(enc.as_bytes());
    out
}

/// Raw X‖Y (64 bytes, no prefix) — `tobytes`.
fn point_xy(p: &ProjectivePoint) -> [u8; 64] {
    let enc = p.to_affine().to_encoded_point(false);
    let mut out = [0u8; 64];
    out.copy_from_slice(&enc.as_bytes()[1..65]);
    out
}

/// X coordinate only (32 bytes).
fn point_x(p: &ProjectivePoint) -> [u8; 32] {
    let enc = p.to_affine().to_encoded_point(false);
    let mut out = [0u8; 32];
    out.copy_from_slice(&enc.as_bytes()[1..33]);
    out
}

/// Parse a point from raw X‖Y (64 bytes) — `frombytes`.
fn point_from_xy(data: &[u8]) -> Result<ProjectivePoint, String> {
    let mut buf = [0u8; 65];
    buf[0] = 0x04;
    buf[1..65].copy_from_slice(&data[0..64]);
    let ep = EncodedPoint::from_bytes(buf).map_err(|e| format!("bad point: {e}"))?;
    let aff = AffinePoint::from_encoded_point(&ep);
    if aff.is_some().into() {
        Ok(ProjectivePoint::from(aff.unwrap()))
    } else {
        Err("point not on curve".into())
    }
}

/// 4-byte big-endian length prefix — `setnum`.
fn push_be_len(buf: &mut Vec<u8>, len: usize) {
    buf.extend_from_slice(&(len as u32).to_be_bytes());
}

/// Schnorr challenge hash `c = SHA256( len‖p1 ‖ len‖gv ‖ len‖pubkey ‖ len‖party ) mod n`.
/// Buffer order matches `mkhash(p1, gv, pub_key, party)` (ecJPake.cpp:308-331).
fn hash_challenge(
    p1: &ProjectivePoint,
    gv: &ProjectivePoint,
    pubkey: &ProjectivePoint,
    party: &[u8; 6],
) -> Scalar {
    let mut buf = Vec::with_capacity(4 * 4 + 6 + 3 * 65);
    for pt in [p1, gv, pubkey] {
        push_be_len(&mut buf, 65);
        buf.extend_from_slice(&point_uncompressed(pt));
    }
    push_be_len(&mut buf, party.len());
    buf.extend_from_slice(party);
    let digest = Sha256::digest(&buf);
    let mut h = [0u8; 32];
    h.copy_from_slice(&digest);
    scalar_from_be(&h)
}

// --- cert (one public key + its Schnorr proof) -----------------------------

/// A `PCert`: pubkey1 (the public key), pubkey2 (the ZKP commitment gv = v·p1),
/// and the 32-byte proof scalar `r = v - c·priv (mod n)`.
#[derive(Clone)]
struct PCert {
    pubkey1: ProjectivePoint,
    pubkey2: ProjectivePoint,
    proof: Scalar,
}

impl PCert {
    /// `PCert::fill` — build a proof for `pubkey` over base `p1` with private
    /// scalar `priv_key` and commitment nonce `rannum`. Our (phone) proofs use
    /// PARTY_A; the sensor uses PARTY_B.
    fn fill(
        p1: &ProjectivePoint,
        pubkey: &ProjectivePoint,
        priv_key: &Scalar,
        rannum: &Scalar,
        party: &[u8; 6],
    ) -> PCert {
        let gv = *p1 * rannum; // gv = rannum · p1
        let c = hash_challenge(p1, &gv, pubkey, party);
        let proof = *rannum - (c * priv_key); // r = v - c·priv  (mod n)
        PCert { pubkey1: *pubkey, pubkey2: gv, proof }
    }

    /// `byteify` — 160-byte wire payload.
    fn to_bytes(&self) -> [u8; 160] {
        let mut out = [0u8; 160];
        out[0..64].copy_from_slice(&point_xy(&self.pubkey1));
        out[64..128].copy_from_slice(&point_xy(&self.pubkey2));
        out[128..160].copy_from_slice(&self.proof.to_bytes());
        out
    }

    /// `frombytes` — parse a 160-byte payload.
    fn from_bytes(data: &[u8]) -> Result<PCert, String> {
        if data.len() < 160 {
            return Err(format!("cert payload too short: {}", data.len()));
        }
        let pubkey1 = point_from_xy(&data[0..64])?;
        let pubkey2 = point_from_xy(&data[64..128])?;
        let mut pb = [0u8; 32];
        pb.copy_from_slice(&data[128..160]);
        let proof =
            Option::<Scalar>::from(Scalar::from_repr(pb.into())).ok_or("proof scalar >= n")?;
        Ok(PCert { pubkey1, pubkey2, proof })
    }

    /// Verify the ZKP: `p1·r + pubkey1·c == pubkey2`, with `c` over `party`.
    /// (ecJPake.cpp:551-565, implemented correctly here for our own checks.)
    fn verify(&self, p1: &ProjectivePoint, party: &[u8; 6]) -> bool {
        let c = hash_challenge(p1, &self.pubkey2, &self.pubkey1, party);
        let lhs = (*p1 * self.proof) + (self.pubkey1 * c);
        lhs == self.pubkey2
    }
}

// --- public opaque handshake object (exposed to Dart via FRB) --------------

/// Stateful EC-JPAKE handshake for one G7 pairing. Methods drive the
/// `ExchangePakePayload` (0x0A) rounds and the final AES key confirmation.
pub struct G7Jpake {
    inner: Mutex<Inner>,
}

struct Inner {
    pass: Scalar,        // pairing code (4 ASCII bytes), reduced mod n
    x1: Scalar,          // our key[0] private
    g1: ProjectivePoint, // our key[0] public = x1·G
    x2: Scalar,          // our key[1] private
    g2: ProjectivePoint, // our key[1] public = x2·G
    sensor_g3: Option<ProjectivePoint>, // certs[0].pubkey1
    sensor_g4: Option<ProjectivePoint>, // certs[1].pubkey1
    sensor_b: Option<ProjectivePoint>,  // certs[2].pubkey1 (sensor round-3 A)
    shared_key: Option<[u8; 16]>,
}

impl G7Jpake {
    /// Initialise with the sensor pairing code (the 4-character applicator code).
    /// Generates the two ephemeral keypairs (x1, x2).
    #[flutter_rust_bridge::frb(sync)]
    pub fn new(pairing_code: String) -> Result<G7Jpake, String> {
        let pin = pairing_code.as_bytes();
        if pin.is_empty() || pin.len() > 32 {
            return Err("pairing code must be 1..32 bytes".into());
        }
        let mut pinbuf = [0u8; 32];
        pinbuf[32 - pin.len()..].copy_from_slice(pin); // right-aligned, like BN_bin2bn
        let pass = scalar_from_be(&pinbuf);

        let mut rng = rand_core::OsRng;
        let x1 = *NonZeroScalar::random(&mut rng);
        let x2 = *NonZeroScalar::random(&mut rng);
        let g = ProjectivePoint::GENERATOR;
        Ok(G7Jpake {
            inner: Mutex::new(Inner {
                pass,
                x1,
                g1: g * x1,
                x2,
                g2: g * x2,
                sensor_g3: None,
                sensor_g4: None,
                sensor_b: None,
                shared_key: None,
            }),
        })
    }

    /// Round-1 payload (our key[0]) for `ExchangePakePayload` phase 0.
    #[flutter_rust_bridge::frb(sync)]
    pub fn round1_payload(&self) -> Vec<u8> {
        let g = self.inner.lock().unwrap();
        let v = random_scalar();
        PCert::fill(&ProjectivePoint::GENERATOR, &g.g1, &g.x1, &v, &PARTY_A).to_bytes().to_vec()
    }

    /// Round-2 payload (our key[1]) for `ExchangePakePayload` phase 1.
    #[flutter_rust_bridge::frb(sync)]
    pub fn round2_payload(&self) -> Vec<u8> {
        let g = self.inner.lock().unwrap();
        let v = random_scalar();
        PCert::fill(&ProjectivePoint::GENERATOR, &g.g2, &g.x2, &v, &PARTY_A).to_bytes().to_vec()
    }

    /// Store the sensor's round-1 (phase 0) cert. Returns whether its ZKP verifies.
    #[flutter_rust_bridge::frb(sync)]
    pub fn set_sensor_round1(&self, payload: Vec<u8>) -> Result<bool, String> {
        let cert = PCert::from_bytes(&payload)?;
        let ok = cert.verify(&ProjectivePoint::GENERATOR, &PARTY_B);
        self.inner.lock().unwrap().sensor_g3 = Some(cert.pubkey1);
        Ok(ok)
    }

    /// Store the sensor's round-2 (phase 1) cert. Returns whether its ZKP verifies.
    #[flutter_rust_bridge::frb(sync)]
    pub fn set_sensor_round2(&self, payload: Vec<u8>) -> Result<bool, String> {
        let cert = PCert::from_bytes(&payload)?;
        let ok = cert.verify(&ProjectivePoint::GENERATOR, &PARTY_B);
        self.inner.lock().unwrap().sensor_g4 = Some(cert.pubkey1);
        Ok(ok)
    }

    /// Our round-3 payload (`makeRound3Cert`) for `ExchangePakePayload` phase 2.
    /// Requires both sensor round-1 and round-2 to have been set.
    #[flutter_rust_bridge::frb(sync)]
    pub fn round3_payload(&self) -> Result<Vec<u8>, String> {
        let g = self.inner.lock().unwrap();
        let g3 = g.sensor_g3.ok_or("sensor round1 not set")?;
        let g4 = g.sensor_g4.ok_or("sensor round2 not set")?;
        let x2s = g.x2 * g.pass; // x2·s mod n
        let g134 = g.g1 + g3 + g4; // pubA + sensorG3 + sensorG4
        let a = g134 * x2s; // A = (x2·s)·g134
        let ran3 = scalar_from_hex(ROUND3_EXPONENT_HEX);
        Ok(PCert::fill(&g134, &a, &x2s, &ran3, &PARTY_A).to_bytes().to_vec())
    }

    /// Store the sensor's round-3 cert and derive the shared session key.
    /// Returns the 16-byte AES-128 session key.
    #[flutter_rust_bridge::frb(sync)]
    pub fn set_sensor_round3(&self, payload: Vec<u8>) -> Result<Vec<u8>, String> {
        let cert = PCert::from_bytes(&payload)?;
        let mut g = self.inner.lock().unwrap();
        g.sensor_b = Some(cert.pubkey1);
        let g4 = g.sensor_g4.ok_or("sensor round2 not set")?;
        let key = derive_shared_key(&cert.pubkey1, &g4, &g.pass, &g.x2);
        g.shared_key = Some(key);
        Ok(key.to_vec())
    }

    /// The derived 16-byte session key (after `set_sensor_round3`).
    #[flutter_rust_bridge::frb(sync)]
    pub fn shared_key(&self) -> Result<Vec<u8>, String> {
        self.inner
            .lock()
            .unwrap()
            .shared_key
            .map(|k| k.to_vec())
            .ok_or("shared key not derived yet".into())
    }

    /// AES key-confirmation primitive (`encrypt8AES`): AES-128-ECB of the 8-byte
    /// input (doubled to a 16-byte block), returning the first 8 bytes. Used for
    /// opcodes 0x02/0x04. Key = the derived session key.
    #[flutter_rust_bridge::frb(sync)]
    pub fn aes8(&self, data8: Vec<u8>) -> Result<Vec<u8>, String> {
        if data8.len() < 8 {
            return Err("aes8 needs 8 bytes".into());
        }
        let key = self.inner.lock().unwrap().shared_key.ok_or("no session key")?;
        Ok(encrypt8_aes(&key, &data8[0..8]).to_vec())
    }
}

/// Embedded Dexcom display-certificate signing key (`getKeyC` in ecJPake.cpp).
/// 31-byte BN_bin2bn value, zero-padded to 32. Its public key is the leaf cert
/// (`certs[1]`) the reader presents during the 0x0B exchange.
const DISPLAY_PRIV_KEY: [u8; 32] = [
    ***REMOVED***
    ***REMOVED***
];

impl G7Jpake {
    /// Proof-of-possession (`0x0C`): sign SHA-256 of the sensor's 16-byte
    /// challenge (`challenge[2..18]`) with the embedded display key, returning a
    /// 64-byte raw `r‖s` ECDSA-P256 signature. (Juggluco `getchallenge`.)
    #[flutter_rust_bridge::frb(sync)]
    pub fn pop_sign(&self, challenge: Vec<u8>) -> Result<Vec<u8>, String> {
        if challenge.len() < 18 {
            return Err("PoP challenge must be >= 18 bytes".into());
        }
        let digest = Sha256::digest(&challenge[2..18]);
        let sk = p256::ecdsa::SigningKey::from_bytes(&DISPLAY_PRIV_KEY.into())
            .map_err(|e| format!("bad display key: {e}"))?;
        use p256::ecdsa::signature::hazmat::PrehashSigner;
        let sig: p256::ecdsa::Signature =
            sk.sign_prehash(&digest).map_err(|e| format!("sign failed: {e}"))?;
        Ok(sig.to_bytes().to_vec())
    }
}

/// Reconnect-path AES key confirmation using a previously-derived session key
/// (no J-PAKE needed). Same primitive as `G7Jpake::aes8`. Returns the 8-byte
/// AES-128-ECB block for opcodes 0x02/0x04.
#[flutter_rust_bridge::frb(sync)]
pub fn aes8_with_key(session_key: Vec<u8>, data8: Vec<u8>) -> Result<Vec<u8>, String> {
    if session_key.len() < 16 {
        return Err("session key must be 16 bytes".into());
    }
    if data8.len() < 8 {
        return Err("aes8 needs 8 bytes".into());
    }
    let mut key = [0u8; 16];
    key.copy_from_slice(&session_key[0..16]);
    Ok(encrypt8_aes(&key, &data8[0..8]).to_vec())
}

fn random_scalar() -> Scalar {
    let mut rng = rand_core::OsRng;
    *NonZeroScalar::random(&mut rng)
}

/// `mkSharedKey`: K = SHA256( X( x2 · (B - (x2·s)·G4) ) )[0:16].
fn derive_shared_key(
    sensor_b: &ProjectivePoint,
    sensor_g4: &ProjectivePoint,
    pass: &Scalar,
    x2: &Scalar,
) -> [u8; 16] {
    let num = *x2 * pass; // x2·s mod n
    let key_point = (*sensor_b - (*sensor_g4 * num)) * x2;
    let x = point_x(&key_point);
    let digest = Sha256::digest(x);
    let mut out = [0u8; 16];
    out.copy_from_slice(&digest[0..16]);
    out
}

fn encrypt8_aes(key16: &[u8; 16], data8: &[u8]) -> [u8; 8] {
    let mut block = [0u8; 16];
    block[0..8].copy_from_slice(&data8[0..8]);
    block[8..16].copy_from_slice(&data8[0..8]);
    let cipher = Aes128::new(key16.into());
    cipher.encrypt_block((&mut block).into());
    let mut out = [0u8; 8];
    out.copy_from_slice(&block[0..8]);
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    // Point sources for the round-3 KAT (Juggluco's packby1/packby2). Their
    // pubkey1 fields are used as the peer's G3/G4; their ZKPs are not asserted
    // (Juggluco's own `validate` uses an inverted EC_POINT_cmp, so these blobs
    // are not validly-signed certs — they're just point fixtures).
    const PACKBY1: &str = "7ccc36e133643a357a1ffba9a2a266246ed504697f4ba03e6b2f4e7b62b4bb88b47e39052e0c11f525f344d6b3b0924f3d33cc25775b8a55cdc6117a518cff262cc2267b156f5bfc4bbbb0f93bf1f9ce09e17d621398c2b36e0acd772e713a77b14e175ae07b943411918fcfed480066a47c06f4c25b01cb20b148c036819f4afed6f7aaf7dfcfbcf0965ae8e11900022e9298b6a546b14769cbfee1c77b9170";
    const PACKBY2: &str = "0b7d5bc678f018f2d0d86ef4b982813e7f501c0d142975efda08e539dbf8e04d0ab6fd611dbcfe1bafd46a2fb806640c75872a2186b747a6afb8bea721e381bf823e7be9be45757c219f6a9f0f5d2d9de01cd05d3d72c911d0bae22c48ef05717ad3fc962bc47915f983285c4b78174be1d63151725dec834c4cf0769b44f8367dffb961d2a174bf3f8148707e5dae974adffb3f41c3e378a8c44d8666168ef3";

    // Deterministic reference vectors captured from Juggluco's actual compiled
    // ecJPake.cpp `testmulti()` (OpenSSL). Byte-exact match here proves our port
    // is identical to the working implementation.
    const PRIV_A: &str = "54fd40eafbe36079e92056a79b7b69c672fb35452179a3f3a30c00402c4a71c3";
    const RAN1: &str = "fbc271b637e2491e45a4179ed33665c506a1e0a1d350f5af0f96370695fdc323";
    const PRIV_B: &str = "95ae54cd1f1542b9aa55df0b246ec9b9acd41668da8ed3c13424907948a9d18f";
    const PACKET1: &str = "6c0314694f6717cff37644dea59b057efce2df4ffc0520ee41f657b6206596a1ec1946cf6844c92d58127d9a3f1b2ec2f0166d2d7c18476eaf863e312a3e8f1eb65cadad5784894de54209a371c13a40af7ba96787c1e5ce0744d4c9c741b886aa0c5b7f2a4dce1f3663bd2397e8c6466eec3a742f8e8d244db1ef086f12128f3795d49b3adb9e37e4debd4e8c3c3f2b589fff088e497404c7c2306b9e5564ee";
    const BYTE3: &str = "a4dcfae2e05f847314eb35ec93fe0343371ce40badedf3428f4ffaa733edc3762d3e0d1c037246c4b6881849bef46d274a3ad9a73ea262a3944a5db066019ea105ee9db54bff6826524622c1ece5aa2451079220ca11b1f9a6b2d81fe398eb229c36c16c54829e066b47c6c9d4ec7f928bb14530f18b792f2e79e3bb3197788d5d7b73db10dc19151e937aff97426d43837fe3b1a95e4080648ee1c49fd00559";
    const SHARED_KEY: &str = "6f8326744bef03faa520ad9c5cff673f";

    fn unhex(s: &str) -> Vec<u8> {
        (0..s.len() / 2)
            .map(|i| u8::from_str_radix(&s[i * 2..i * 2 + 2], 16).unwrap())
            .collect()
    }
    fn hexs(b: &[u8]) -> String {
        b.iter().map(|x| format!("{x:02x}")).collect()
    }
    fn pass_scalar(code: &str) -> Scalar {
        let mut p = [0u8; 32];
        p[32 - code.len()..].copy_from_slice(code.as_bytes());
        scalar_from_be(&p)
    }

    // BYTE-EXACT known-answer tests vs. Juggluco's compiled reference output.
    #[test]
    fn kat_round1_round2_payloads() {
        let g = ProjectivePoint::GENERATOR;
        let priv_a = scalar_from_hex(PRIV_A);
        let c1 = PCert::fill(&g, &(g * priv_a), &priv_a, &scalar_from_hex(RAN1), &PARTY_A);
        assert_eq!(hexs(&c1.to_bytes()), PACKET1, "round-1 payload must match Juggluco");
    }

    #[test]
    fn kat_round3_and_shared_key() {
        let g = ProjectivePoint::GENERATOR;
        let priv_a = scalar_from_hex(PRIV_A);
        let priv_b = scalar_from_hex(PRIV_B);
        let pass = pass_scalar("1155");
        let pub_a = g * priv_a;
        let g3 = PCert::from_bytes(&unhex(PACKBY1)).unwrap().pubkey1;
        let g4_cert = PCert::from_bytes(&unhex(PACKBY2)).unwrap();
        let g4 = g4_cert.pubkey1;

        // makeRound3Cert: g134 = pubA + G3 + G4; A = (privB·pass)·g134.
        let x2s = priv_b * pass;
        let g134 = pub_a + g3 + g4;
        let a = g134 * x2s;
        let ran3 = scalar_from_hex(ROUND3_EXPONENT_HEX);
        let cert3 = PCert::fill(&g134, &a, &x2s, &ran3, &PARTY_A);
        assert_eq!(hexs(&cert3.to_bytes()), BYTE3, "round-3 payload must match Juggluco");

        // mkSharedKey(cert2=packby2, cert3=our round3, pass, x2=privB).
        let key = derive_shared_key(&cert3.pubkey1, &g4, &pass, &priv_b);
        assert_eq!(hexs(&key), SHARED_KEY, "shared key must match Juggluco");
    }

    // The embedded display private key must match the leaf certificate's public
    // key (certs[1], 0451 18c3…). A PoP signature it produces must verify under
    // that public key — proving the key pairing is correct.
    #[test]
    fn pop_signature_verifies_under_leaf_cert() {
        const LEAF_PUB: &str = "***REMOVED***";
        let jpake = G7Jpake::new("1155".into()).unwrap();
        // 0x0C ‖ 16-byte challenge.
        let mut challenge = vec![0x0c, 0x00];
        challenge.extend_from_slice(&unhex("0cee691b765a497d225823d14f278dd3"));
        let sig_bytes = jpake.pop_sign(challenge.clone()).unwrap();
        assert_eq!(sig_bytes.len(), 64, "r||s must be 64 bytes");

        use p256::ecdsa::signature::hazmat::PrehashVerifier;
        let vk = p256::ecdsa::VerifyingKey::from_sec1_bytes(&unhex(LEAF_PUB)).unwrap();
        let sig = p256::ecdsa::Signature::from_slice(&sig_bytes).unwrap();
        let digest = sha2::Sha256::digest(&challenge[2..18]);
        assert!(vk.verify_prehash(&digest, &sig).is_ok(), "PoP sig must verify under leaf cert key");
    }

    #[test]
    fn kat_encrypt8_aes() {
        let mut key = [0u8; 16];
        key.copy_from_slice(&unhex("6f8326744bef03faa520ad9c5cff673f"));
        let out = encrypt8_aes(&key, &unhex("2a404290c4b63b01"));
        assert_eq!(hexs(&out), "13ab13f6975e3082", "AES-128 key confirmation must match");
    }

    #[test]
    fn our_proof_verifies_and_roundtrips() {
        let g = ProjectivePoint::GENERATOR;
        let x = random_scalar();
        let pubkey = g * x;
        let v = random_scalar();
        let cert = PCert::fill(&g, &pubkey, &x, &v, &PARTY_A);
        assert!(cert.verify(&g, &PARTY_A));
        let parsed = PCert::from_bytes(&cert.to_bytes()).unwrap();
        assert!(parsed.verify(&g, &PARTY_A));
    }

    // Full two-party J-PAKE: phone (our public API) vs. a simulated sensor.
    // Both must derive an identical 16-byte session key.
    #[test]
    fn full_handshake_agrees_on_key() {
        let g = ProjectivePoint::GENERATOR;
        let code = "1155";
        let mut pinbuf = [0u8; 32];
        pinbuf[28..].copy_from_slice(code.as_bytes());
        let s = scalar_from_be(&pinbuf);

        // Phone side via the public FRB API.
        let phone = G7Jpake::new(code.into()).unwrap();
        let (g1, g2) = {
            let i = phone.inner.lock().unwrap();
            (i.g1, i.g2)
        };

        // Sensor side (simulated): keys y1, y2; proofs use PARTY_B.
        let y1 = random_scalar();
        let y2 = random_scalar();
        let sg3 = g * y1;
        let sg4 = g * y2;
        let s_r1 = PCert::fill(&g, &sg3, &y1, &random_scalar(), &PARTY_B).to_bytes();
        let s_r2 = PCert::fill(&g, &sg4, &y2, &random_scalar(), &PARTY_B).to_bytes();

        // Phone consumes sensor round1/round2 — ZKPs must verify.
        assert!(phone.set_sensor_round1(s_r1.to_vec()).unwrap(), "sensor r1 ZKP");
        assert!(phone.set_sensor_round2(s_r2.to_vec()).unwrap(), "sensor r2 ZKP");

        // Phone produces its round-3 A.
        let phone_r3 = phone.round3_payload().unwrap();
        let a_phone = PCert::from_bytes(&phone_r3).unwrap().pubkey1;

        // Sensor produces its round-3 B = (y2·s)·(sg3 + g1 + g2).
        let y2s = y2 * s;
        let base_sensor = sg3 + g1 + g2;
        let b_sensor = base_sensor * y2s;
        let s_r3 = PCert::fill(&base_sensor, &b_sensor, &y2s, &random_scalar(), &PARTY_B).to_bytes();

        // Phone derives its key from the sensor's B.
        let phone_key = phone.set_sensor_round3(s_r3.to_vec()).unwrap();

        // Sensor derives its key from the phone's A: K = y2·(A - y2·s·G2), G2 = phone g2.
        let sensor_key = derive_shared_key(&a_phone, &g2, &s, &y2);

        assert_eq!(phone_key, sensor_key.to_vec(), "phone/sensor session keys must match");
        assert_eq!(phone_key.len(), 16);
    }
}

