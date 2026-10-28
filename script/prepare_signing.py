"""Create a project-local signing identity. Does not install a global trust root."""
from pathlib import Path
import os
import secrets
import shlex
import subprocess
import sys

root=Path(sys.argv[1]).resolve()
directory=root/'work/signing'
directory.mkdir(parents=True,exist_ok=True,mode=0o700)
os.chmod(directory,0o700)
password_file=directory/'password'
if not password_file.exists():
    password_file.write_text(secrets.token_hex(32)); os.chmod(password_file,0o600)
password=password_file.read_text().strip()
keychain=directory/'development.keychain-db'
def run(args):
    result=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or f'Command failed: {args[0]}')
    return result.stdout
if not keychain.exists():
    config=directory/'certificate.cnf'
    config.write_text('[req]\nprompt=no\ndistinguished_name=dn\nx509_extensions=ext\n[dn]\nCN=KeyBridge Local Development\n[ext]\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=codeSigning\nsubjectKeyIdentifier=hash\n')
    run(['/usr/bin/openssl','req','-new','-newkey','rsa:2048','-nodes','-x509','-sha256','-days','3650','-config',str(config),'-keyout',str(directory/'private.pem'),'-out',str(directory/'certificate.pem')])
    os.chmod(directory/'private.pem',0o600)
    run(['/usr/bin/openssl','pkcs12','-export','-inkey',str(directory/'private.pem'),'-in',str(directory/'certificate.pem'),'-out',str(directory/'identity.p12'),'-passout','file:'+str(password_file)])
    os.chmod(directory/'identity.p12',0o600)
    original=shlex.split(run(['/usr/bin/security','list-keychains','-d','user']))
    try:
        run(['/usr/bin/security','create-keychain','-p',password,str(keychain)])
        run(['/usr/bin/security','unlock-keychain','-p',password,str(keychain)])
        run(['/usr/bin/security','import',str(directory/'identity.p12'),'-k',str(keychain),'-P',password,'-T','/usr/bin/codesign'])
        run(['/usr/bin/security','set-key-partition-list','-S','apple-tool:,apple:,codesign:','-s','-k',password,str(keychain)])
    finally:
        run(['/usr/bin/security','list-keychains','-d','user','-s',*original])
run(['/usr/bin/security','unlock-keychain','-p',password,str(keychain)])
run(['/usr/bin/security','set-keychain-settings','-lut','21600',str(keychain)])
fingerprint=run(['/usr/bin/openssl','x509','-in',str(directory/'certificate.pem'),'-noout','-sha1','-fingerprint']).strip().split('=')[-1].replace(':','')
(directory/'identity.sha1').write_text(fingerprint)
if len(sys.argv) > 3 and sys.argv[2] == '--sign':
    original=shlex.split(run(['/usr/bin/security','list-keychains','-d','user']))
    try:
        run(['/usr/bin/security','list-keychains','-d','user','-s',*original,str(keychain)])
        run(['/usr/bin/codesign','--force','--sign',fingerprint,'--keychain',str(keychain),'--options','runtime','--timestamp=none',sys.argv[3]])
    finally:
        run(['/usr/bin/security','list-keychains','-d','user','-s',*original])
else:
    print(fingerprint)
