/* Mbed TLS 3.6 – schmale Konfiguration für Uzais WebRTC-Datenkanal (tools/bau_netzlibs.sh).
 * Nur DTLS 1.2 mit ECDHE-ECDSA und AEAD (AES-GCM, ChaCha20-Poly1305); kein TLS 1.3, kein CBC,
 * keine RSA-Schlüsseltausche, keine Netzwerk-Sockets in Mbed TLS (die Pakete kommen von libjuice),
 * kein Debug-Ausgang. RSA_C steht nur drin, weil libdatachannel den RSA-Zertifikatsweg mit
 * übersetzt; Uzai erzeugt nur ECDSA-Zertifikate, und ohne RSA-Schlüsseltausch kann ein RSA-Zertifikat
 * keinen Handschlag tragen. */
#ifndef UZAI_MBEDTLS_CONFIG_H
#define UZAI_MBEDTLS_CONFIG_H

/* Plattform (Windows verlangt PLATFORM_C für snprintf) */
#define MBEDTLS_PLATFORM_C
#define MBEDTLS_HAVE_ASM
#define MBEDTLS_HAVE_TIME
#define MBEDTLS_HAVE_TIME_DATE
#define MBEDTLS_FS_IO              /* von libdatachannel gelinkt; Uzai übergibt nie Dateien (und der Container hat keine) */
#define MBEDTLS_NO_UDBL_DIVISION

/* Zufall */
#define MBEDTLS_ENTROPY_C
#define MBEDTLS_CTR_DRBG_C
#define MBEDTLS_HMAC_DRBG_C

/* Hashes, Chiffren */
#define MBEDTLS_MD_C
#define MBEDTLS_SHA1_C             /* nur für Fingerabdrücke anderer Längen, nie in Signaturen ausgehandelt */
#define MBEDTLS_SHA224_C
#define MBEDTLS_SHA256_C
#define MBEDTLS_SHA384_C
#define MBEDTLS_SHA512_C
#define MBEDTLS_AES_C
#define MBEDTLS_AESNI_C
#define MBEDTLS_GCM_C
#define MBEDTLS_CHACHA20_C
#define MBEDTLS_POLY1305_C
#define MBEDTLS_CHACHAPOLY_C
#define MBEDTLS_CIPHER_C

/* Öffentliche Schlüssel */
#define MBEDTLS_BIGNUM_C
#define MBEDTLS_ECP_C
#define MBEDTLS_ECP_DP_SECP256R1_ENABLED
#define MBEDTLS_ECP_DP_SECP384R1_ENABLED
#define MBEDTLS_ECP_DP_CURVE25519_ENABLED
#define MBEDTLS_ECP_NIST_OPTIM
#define MBEDTLS_ECDH_C
#define MBEDTLS_ECDSA_C
#define MBEDTLS_ECDSA_DETERMINISTIC
#define MBEDTLS_RSA_C
#define MBEDTLS_PKCS1_V15
#define MBEDTLS_PKCS1_V21
#define MBEDTLS_GENPRIME
#define MBEDTLS_ASN1_PARSE_C
#define MBEDTLS_ASN1_WRITE_C
#define MBEDTLS_OID_C
#define MBEDTLS_PK_C
#define MBEDTLS_PK_PARSE_C
#define MBEDTLS_PK_WRITE_C
#define MBEDTLS_BASE64_C
#define MBEDTLS_PEM_PARSE_C

/* X.509: eigenes Zertifikat erzeugen, das der Gegenstelle lesen (geprüft wird der Fingerabdruck) */
#define MBEDTLS_X509_USE_C
#define MBEDTLS_X509_CRT_PARSE_C
#define MBEDTLS_X509_CREATE_C
#define MBEDTLS_X509_CRT_WRITE_C
#define MBEDTLS_X509_MAX_INTERMEDIATE_CA 1

/* DTLS 1.2 */
#define MBEDTLS_SSL_TLS_C
#define MBEDTLS_SSL_CLI_C
#define MBEDTLS_SSL_SRV_C
#define MBEDTLS_SSL_PROTO_TLS1_2
#define MBEDTLS_SSL_PROTO_DTLS
#define MBEDTLS_SSL_DTLS_ANTI_REPLAY
#define MBEDTLS_SSL_DTLS_HELLO_VERIFY
#define MBEDTLS_SSL_DTLS_SRTP      /* libdatachannel setzt die SRTP-Liste immer; ohne Medien wird nie ein Schlüssel benutzt */
#define MBEDTLS_SSL_KEEP_PEER_CERTIFICATE
#define MBEDTLS_SSL_EXTENDED_MASTER_SECRET
#define MBEDTLS_SSL_SERVER_NAME_INDICATION
#define MBEDTLS_KEY_EXCHANGE_ECDHE_ECDSA_ENABLED
#define MBEDTLS_SSL_CIPHERSUITES \
    MBEDTLS_TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256, \
    MBEDTLS_TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384, \
    MBEDTLS_TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256

#define MBEDTLS_ERROR_C

#endif
