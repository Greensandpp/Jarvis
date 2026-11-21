"""Encrypt a built APK for private ChatGPT retrieval.

Public GitHub Actions artifacts must NOT contain plaintext APKs.
Format: ASCII GSV1, 2-byte big-endian wrapped-key length,
RSA-OAEP(SHA256)-wrapped random AES-256 key, 12-byte random nonce,
AES-GCM ciphertext+authentication tag.
Only the encryption PUBLIC key is placed in this public repository.
"""
from pathlib import Path
import secrets
import sys
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

def main():
    if len(sys.argv) != 4:
        raise SystemExit("usage: encrypt_apk.py PUBLIC_PEM APK_FILE OUTPUT")
    pub = serialization.load_pem_public_key(Path(sys.argv[1]).read_bytes())
    apk = Path(sys.argv[2]).read_bytes()
    if not apk.startswith(b"PK"):
        # APKs are ZIP archives. Do not encrypt a failed or missing build.
        raise SystemExit("input is not a ZIP-compatible APK")
    key = AESGCM.generate_key(bit_length=256)
    wrapped = pub.encrypt(
        key, padding.OAEP(mgf=padding.MGF1(hashes.SHA256()),
                          algorithm=hashes.SHA256(), label=None))
    nonce = secrets.token_bytes(12)
    header = b"GSV1" + len(wrapped).to_bytes(2, "big") + wrapped + nonce
    data = AESGCM(key).encrypt(nonce, apk, header)
    Path(sys.argv[3]).write_bytes(header + data)
    print("Encrypted APK verified. Raw APK will not be uploaded.")

if __name__ == "__main__":
    main()
