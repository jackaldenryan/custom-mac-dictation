#!/usr/bin/env bash
set -euo pipefail

identity="${CODESIGN_IDENTITY:-Custom Dictation Signing}"
support="${HOME}/Library/Application Support/CustomDictation/signing"
p12="$support/CustomDictationSigning.p12"
pass_file="$support/p12-password"
keychain_name="custom-dictation-signing"
keychain_pass_file="$support/keychain-password"

mkdir -p "$support"
chmod 700 "$support"

if [[ ! -f "$pass_file" ]]; then
  /usr/bin/openssl rand -base64 24 > "$pass_file"
  chmod 600 "$pass_file"
fi
if [[ ! -f "$keychain_pass_file" ]]; then
  /usr/bin/openssl rand -base64 24 > "$keychain_pass_file"
  chmod 600 "$keychain_pass_file"
fi

p12_pass="$(tr -d '[:space:]' < "$pass_file")"
keychain_pass="$(tr -d '[:space:]' < "$keychain_pass_file")"

if [[ -n "${CODESIGN_P12:-}" ]]; then
  echo "$CODESIGN_P12" | /usr/bin/base64 -d > "$p12"
  chmod 600 "$p12"
fi

if [[ ! -f "$p12" ]]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  cat > "$tmp/openssl.cnf" <<'EOF'
[req]
distinguished_name = req_distinguished_name
prompt = no
x509_extensions = ext

[req_distinguished_name]
CN = Custom Dictation Signing
O = Custom Dictation

[ext]
basicConstraints = critical, CA:TRUE
keyUsage = critical, digitalSignature, keyCertSign
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF
  /usr/bin/openssl req -new -x509 -days 3650 -nodes \
    -config "$tmp/openssl.cnf" \
    -keyout "$tmp/key.pem" \
    -out "$tmp/cert.pem"
  /usr/bin/openssl pkcs12 -export \
    -inkey "$tmp/key.pem" \
    -in "$tmp/cert.pem" \
    -out "$p12" \
    -passout "pass:$p12_pass" \
    -name "$identity"
  chmod 600 "$p12"
fi

if [[ ! -e "$HOME/Library/Keychains/${keychain_name}-db" && ! -e "$HOME/Library/Keychains/${keychain_name}.keychain-db" ]]; then
  security create-keychain -p "$keychain_pass" "$keychain_name"
fi
security set-keychain-settings -lut 21600 "$keychain_name"
security unlock-keychain -p "$keychain_pass" "$keychain_name"
security list-keychains -d user -s "$keychain_name" login.keychain-db
security import "$p12" -k "$keychain_name" -P "$p12_pass" -T /usr/bin/codesign -T /usr/bin/security -A >/dev/null 2>&1 || true
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_pass" "$keychain_name" >/dev/null

cert_tmp="$(mktemp)"
/usr/bin/openssl pkcs12 -in "$p12" -clcerts -nokeys -passin "pass:$p12_pass" -out "$cert_tmp" >/dev/null 2>&1
security add-trusted-cert -d -r trustRoot -p codeSign -k "$keychain_name" "$cert_tmp" >/dev/null 2>&1 || true
rm -f "$cert_tmp"

echo "$identity"
