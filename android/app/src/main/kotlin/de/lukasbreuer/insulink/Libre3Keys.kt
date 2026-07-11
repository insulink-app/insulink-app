package de.insulink

// FreeStyle Libre 3 embedded key material, ported verbatim from Juggluco's GPL
// KEYSCrypto.java (LIBRE3_APP_CERTIFICATES_B / LIBRE3_APP_PRIVATE_KEYS). The app
// certificate is public; the private keys are WhiteCryption-SKB-wrapped and only
// usable via the blob's process1/2. Indexed by the sensor's security version.
// Source: github.com/j-kaltes/Juggluco (GPL-3.0). See docs/LIBRE3.md.
object Libre3Keys {
    val appCertificates = arrayOf(
        hex("***REMOVED***"),
        hex("***REMOVED***"),
    )
    val appPrivateKeys = arrayOf(
        hex("***REMOVED***"),
        hex("***REMOVED***"),
    )

    private fun hex(s: String) = ByteArray(s.length / 2) {
        ((s[it * 2].digitToInt(16) shl 4) or s[it * 2 + 1].digitToInt(16)).toByte()
    }
}
