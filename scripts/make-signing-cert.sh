#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Creates a self-signed "OpenGestures Local Dev" code-signing certificate in your login keychain.
# Builds signed with it keep the same identity, so macOS keeps the Accessibility grant across rebuilds.
# macOS asks for your password to trust the certificate. Every build then asks for it again
# ("codesign wants to access key ..."): enter your login password and click Allow, not Always Allow.
# The key is not pre-authorised for codesign, so no other process can sign with it silently.
# Remove it again with scripts/remove-signing-cert.sh.
set -eu
PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin; export PATH
name="OpenGestures Local Dev"
keychain="$HOME/Library/Keychains/login.keychain-db"
trust() {
    security find-certificate -c "$name" -p "$keychain" > "$dir/existing.pem"
    security add-trusted-cert -r trustRoot -p codeSign -k "$keychain" "$dir/existing.pem"
}
if security find-identity -v -p codesigning | grep -q "\"$name\""; then
    echo "\"$name\" already exists."
    exit 0
fi
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
# A certificate from an earlier run that is present but not trusted: trust it again, no duplicate.
if security find-certificate -c "$name" "$keychain" >/dev/null 2>&1; then
    trust
    echo "Trusted the existing \"$name\" certificate. Rebuild with scripts/build-app.sh."
    exit 0
fi
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
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$dir/key.pem" -out "$dir/cert.pem" -days 1825 -config "$dir/c.cnf"
# The PKCS#12 password goes through the environment, so it never shows up in the process list.
OG_P12_PASS=$(openssl rand -hex 12)
export OG_P12_PASS
# -legacy: the macOS keychain cannot import PKCS#12 files using OpenSSL 3+ default algorithms.
legacy=$(openssl pkcs12 -help 2>&1 | grep -q -- -legacy && echo -legacy || true)
openssl pkcs12 -export $legacy -inkey "$dir/key.pem" -in "$dir/cert.pem" -out "$dir/id.p12" -passout env:OG_P12_PASS -name "$name"
# security(1) only takes the import password as an argument. It is a throwaway random value for a
# file in a private temp directory that is deleted on exit.
security import "$dir/id.p12" -k "$keychain" -P "$OG_P12_PASS"
security add-trusted-cert -r trustRoot -p codeSign -k "$keychain" "$dir/cert.pem"
echo "Created \"$name\". Rebuild with scripts/build-app.sh."
