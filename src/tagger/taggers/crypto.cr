require "../../models/tagger"
require "../../models/endpoint"

# Flags endpoints that perform cryptographic operations — encryption /
# decryption, signing / verification, hashing, or key management. These
# warrant review for weak or obsolete algorithms, padding/signing
# oracles, static IV/salt/nonce reuse, and key exposure or mismanagement.
#
# `key`, `sign`, and `verify` are deliberately *not* standalone signals:
# "API key", "sign in", and "verify email" are overwhelmingly non-crypto.
# Bare auth routes (`/signin`, `/signup`) therefore never match here.
class CryptoTagger < Tagger
  # Unambiguous crypto path segments — one is enough. Matched as whole
  # segments after splitting on `/`, `-`, `_`, `.`. Includes named
  # primitives (aes/rsa/sha256/bcrypt/…) and key-management verbs that
  # carry no benign meaning as a standalone path segment. Legacy/weak
  # algorithms (md5/sha1/rc4/3des/blowfish) are kept on purpose — surfacing
  # an endpoint that still uses one is the point of this tag. Each named
  # primitive carries a digit or is otherwise distinctive enough to never
  # collide with a benign word as a whole path segment.
  STRONG_PATH_PARTS = Set{
    "encrypt", "decrypt", "encryption", "decryption", "cipher",
    "crypto", "cryptography", "hmac", "jwks", "jwk", "jwt", "jws", "jwe",
    "keystore", "kms", "pgp", "gpg", "unseal", "x509",
    "pkcs7", "pkcs8", "pkcs12", "pfx",
    "aes", "rsa", "dsa", "ecdsa", "ecdh", "ed25519", "ed448",
    "x25519", "x448", "curve25519", "secp256k1",
    "sha1", "sha224", "sha256", "sha384", "sha512", "sha3", "keccak",
    "ripemd", "ripemd160", "md5", "blake2", "blake3",
    "rc4", "3des", "blowfish", "twofish", "chacha20", "salsa20",
    "bcrypt", "argon2", "scrypt", "pbkdf2", "hkdf", "totp", "hotp",
  }

  # Parameter names that imply a crypto operation on their own (the
  # plaintext/ciphertext payloads, named key material, passphrases).
  STRONG_PARAM_NAMES = Set{
    "plaintext", "ciphertext", "cleartext", "public_key", "private_key",
    "pubkey", "privkey", "secret_key", "signing_key", "encryption_key",
    "decryption_key", "passphrase", "pem", "hmac",
  }

  # Weaker signals: meaningful for crypto but also seen elsewhere. Tag
  # only when at least two *distinct* tokens co-occur (across path and
  # params). `verify`, `iv`, `algo`, and `fingerprint` are intentionally
  # absent — each pairs spuriously with benign tokens (e-sign "verify",
  # invoice "iv", recommendation "algo", device "fingerprint").
  WEAK_PATH_PARTS = Set{
    "signature", "signatures", "signing", "hash", "digest", "checksum",
    "certificate", "cert", "csr",
  }

  WEAK_PARAM_NAMES = Set{
    "signature", "hash", "digest", "algorithm", "salt", "nonce",
    "checksum", "cipher", "key_id", "kid", "certificate", "cert", "csr",
  }

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "crypto"
  end

  def perform(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      param_names = endpoint.params.map { |param| normalize_param_name(param.name) }.to_set
      url_segments = url_parts(endpoint.url)

      has_strong = !(STRONG_PARAM_NAMES & param_names).empty? ||
                   url_segments.any? { |part| STRONG_PATH_PARTS.includes?(part) }

      # Union of distinct weak tokens across path and params. Deduping by
      # token identity prevents one concept echoed in both the path and a
      # query param (e.g. `/cert?cert=…`) — or a path segment repeated
      # (`/certificate/certificate-status`) — from reaching the threshold
      # on its own.
      weak_tokens = WEAK_PARAM_NAMES & param_names
      url_segments.each do |part|
        weak_tokens << part if WEAK_PATH_PARTS.includes?(part)
      end

      check = has_strong || weak_tokens.size >= 2

      if check
        tag = Tag.new(
          "crypto",
          "Cryptographic operation endpoint (encryption/decryption, signing, hashing, or key management); review for weak or obsolete algorithms, padding/signing oracles, static IV/salt/nonce reuse, and key exposure.",
          "Crypto"
        )
        endpoint.add_tag(tag)
      end
    end
  end
end
