#!/bin/bash

# Create a keys directory
mkdir -p files/keys

# Create OpenSSL config
cat > files/keys/openssl.conf << 'EOF'
[req]
distinguished_name = req_distinguished_name
prompt = no
x509_extensions = v3_req

[req_distinguished_name]
CN = DisplayLink EVDI Module Signing Key
O = DisplayLink
OU = EVDI Module
C = US

[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
EOF

# Generate the key pair - ONE TIME ONLY
cd files/keys
openssl req -new -nodes -utf8 -sha256 -days 36500 -batch -x509 \
    -config openssl.conf \
    -outform PEM -out evdi-signing-key.x509 \
    -keyout evdi-signing-key.pem

# Convert the PEM certificate to DER format for MOK enrollment
openssl x509 -outform DER -in evdi-signing-key.x509 -out evdi-signing-key.der

# Clean up config
rm openssl.conf