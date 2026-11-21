#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Creates a self-signed "OpenGestures Local Dev" code-signing certificate in your login keychain.
# Builds signed with it keep the same identity, so macOS keeps the Accessibility grant across rebuilds.
# macOS asks for your password once to trust the certificate for code signing.
set -eu
name="OpenGestures Local Dev"
if security find-identity -v -p codesigning | grep -q "\"$name\""; then
    echo "\"$name\" already exists."
    exit 0
fi
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cat > "$dir/c.cnf" <<CNF
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=$name
[ext]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
CNF
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$dir/key.pem" -out "$dir/cert.pem" -days 3650 -config "$dir/c.cnf" 2>/dev/null
pass=$(openssl rand -hex 12)
# -legacy: the macOS keychain cannot import PKCS#12 files using OpenSSL 3+ default algorithms.
legacy=$(openssl pkcs12 -help 2>&1 | grep -q -- -legacy && echo -legacy || true)
openssl pkcs12 -export $legacy -inkey "$dir/key.pem" -in "$dir/cert.pem" -out "$dir/id.p12" -passout "pass:$pass" -name "$name"
security import "$dir/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$pass" -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign -k "$HOME/Library/Keychains/login.keychain-db" "$dir/cert.pem"
echo "Created \"$name\". Rebuild with scripts/build-app.sh."
