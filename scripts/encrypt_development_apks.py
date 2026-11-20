"""Encrypt development binaries before upload from this public source repo.
Only the workspace recipient private key can recover them. Never publish APKs.
"""
from pathlib import Path
import hashlib,json,os,sys
from cryptography.hazmat.primitives import hashes,serialization
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
public=serialization.load_pem_public_key(Path(sys.argv[1]).read_bytes())
destination=Path(sys.argv[3]);destination.mkdir(parents=True,exist_ok=True)
manifest=[]
for source in sorted(Path(sys.argv[2]).glob('*.apk')):
    data=source.read_bytes();key=AESGCM.generate_key(bit_length=256);nonce=os.urandom(12)
    ciphertext=AESGCM(key).encrypt(nonce,data,source.name.encode())
    wrapped=public.encrypt(key,padding.OAEP(mgf=padding.MGF1(hashes.SHA256()),algorithm=hashes.SHA256(),label=None))
    (destination/(source.name+'.enc')).write_bytes(ciphertext)
    (destination/(source.name+'.json')).write_text(json.dumps({'name':source.name,'nonce':nonce.hex(),'key':wrapped.hex(),'sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data)}))
    manifest.append({'name':source.name,'sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data)})
if not manifest: raise SystemExit('No APKs to encrypt')
(destination/'SHA256SUMS.json').write_text(json.dumps(manifest,indent=2))
