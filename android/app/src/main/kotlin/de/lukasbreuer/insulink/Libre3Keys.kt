package de.insulink

/**
 * FreeStyle Libre 3 key material: the app certificate and the
 * WhiteCryption-SKB-wrapped private key, indexed by the sensor's security
 * version (LIBRE3_APP_CERTIFICATES_B / LIBRE3_APP_PRIVATE_KEYS from Juggluco's
 * KEYSCrypto.java). It is Abbott's, so it is never committed: Gradle bakes it in
 * from the `libre3` section of the gitignored vendor keys (docs/VENDOR_KEYS.md).
 * Without it both lists are empty and the Libre 3 handshake is unavailable.
 */
object Libre3Keys {
    val appCertificates = decodeList(BuildConfig.LIBRE3_CERTIFICATES)
    val appPrivateKeys = decodeList(BuildConfig.LIBRE3_PRIVATE_KEYS)

    /**
     * Whether this build carries everything Libre 3 needs: both key lists and
     * Abbott's blob. Decided at build time, so asking never `dlopen`s the blob.
     */
    val complete get() =
        BuildConfig.LIBRE3_BLOB && appCertificates.isNotEmpty() && appPrivateKeys.isNotEmpty()

    private fun decodeList(joined: String) =
        joined.split(',').filter { entry -> entry.isNotBlank() }.map(::decodeHex)

    private fun decodeHex(hex: String) = ByteArray(hex.length / 2) { index ->
        ((hex[index * 2].digitToInt(16) shl 4) or hex[index * 2 + 1].digitToInt(16)).toByte()
    }
}
