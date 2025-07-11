#!/usr/bin/bash

set -eoux pipefail

# Get module configuration JSON
MODULE_CONFIG_JSON="$1"

# Parse configuration options using jq
RPM_PACKAGE=$(echo "$MODULE_CONFIG_JSON" | jq -r '.options.rpm_package // "/tmp/rpms/displaylink-1.14.9-1.x86_64.rpm"')
SIGNING_KEYS_DIR=$(echo "$MODULE_CONFIG_JSON" | jq -r '.options.signing_keys_dir // "/tmp/keys"')
EVDI_GIT_REPO=$(echo "$MODULE_CONFIG_JSON" | jq -r '.options.evdi_git_repo // "https://github.com/DisplayLink/evdi.git"')
CLEANUP_BUILD_DEPS=$(echo "$MODULE_CONFIG_JSON" | jq -r '.options.cleanup_build_deps // true')
KERNEL_VERSION=$(echo "$MODULE_CONFIG_JSON" | jq -r '.options.kernel_version // "$(uname -r)"')

echo "=== DisplayLink EVDI Module Installation ==="
echo "RPM Package: $RPM_PACKAGE"
echo "Signing Keys Dir: $SIGNING_KEYS_DIR"
echo "EVDI Git Repo: $EVDI_GIT_REPO"
echo "Cleanup Build Deps: $CLEANUP_BUILD_DEPS"

# Install DisplayLink userspace driver from local RPM (skip deps since we handle EVDI ourselves)
echo "Installing DisplayLink userspace driver..."
if [ -f "$RPM_PACKAGE" ]; then
    rpm -i --nodeps "$RPM_PACKAGE"
    echo "DisplayLink RPM installed successfully"
else
    echo "WARNING: DisplayLink RPM not found at $RPM_PACKAGE, skipping RPM installation"
fi

# Build or install evdi module
echo "Setting up EVDI module..."

# Check if we have a pre-built module for this kernel
PREBUILT_MODULE="/tmp/prebuilt-modules/evdi-${KERNEL_VERSION}.ko"

if [ -f "$PREBUILT_MODULE" ]; then
    echo "Using pre-built EVDI module for kernel $KERNEL_VERSION"
    
    # Create module directory if it doesn't exist
    MODULE_DIR="/lib/modules/${KERNEL_VERSION}/extra"
    mkdir -p "$MODULE_DIR"
    
    # Copy the pre-built module
    cp "$PREBUILT_MODULE" "$MODULE_DIR/evdi.ko"
    
    # Update module dependencies
    depmod -a
    
    echo "Pre-built EVDI module installed successfully"
    
else
    echo "No pre-built module found for kernel $KERNEL_VERSION, building from source..."

    # Install required tools
    echo "Installing build dependencies..."
    dnf5 -y install kernel-devel kernel-headers git make gcc libdrm-devel mokutil

    
    # Build evdi module from source
    cd /tmp
    git clone "$EVDI_GIT_REPO"
    cd evdi/module

    # Build with relaxed compiler flags for newer kernel compatibility
    export CFLAGS="-Wno-error=sign-compare -Wno-error=missing-field-initializers -Wno-error=discarded-qualifiers -Wno-error"
    make CFLAGS="$CFLAGS"

    # Install the module
    make install
    
    echo "EVDI module built and installed from source"
fi

# Handle module signing
echo "Setting up module signing..."
TEMP_KEYS_DIR="/tmp/module_signing_keys"
mkdir -p "$TEMP_KEYS_DIR"

# Copy public certificate from repository
if [ -f "$SIGNING_KEYS_DIR/evdi-signing-key.x509" ]; then
    echo "Using public certificate from repository"
    cp "$SIGNING_KEYS_DIR/evdi-signing-key.x509" "$TEMP_KEYS_DIR/signing_key.x509"
else
    echo "ERROR: Public certificate not found at $SIGNING_KEYS_DIR/evdi-signing-key.x509"
    exit 1
fi

# Check if private key is available (from GitHub Secret or local file)
if [ -f "$SIGNING_KEYS_DIR/evdi-signing-key.pem" ]; then
    echo "Using private key from local file"
    cp "$SIGNING_KEYS_DIR/evdi-signing-key.pem" "$TEMP_KEYS_DIR/signing_key.pem"
elif [ -n "${EVDI_SIGNING_KEY_PEM:-}" ]; then
    echo "Using private key from environment variable"
    echo "$EVDI_SIGNING_KEY_PEM" > "$TEMP_KEYS_DIR/signing_key.pem"
else
    echo "ERROR: Private signing key not found"
    echo "Expected: $SIGNING_KEYS_DIR/evdi-signing-key.pem or EVDI_SIGNING_KEY_PEM environment variable"
    exit 1
fi

# Verify keys are accessible
if [ ! -f "$TEMP_KEYS_DIR/signing_key.pem" ] || [ ! -f "$TEMP_KEYS_DIR/signing_key.x509" ]; then
    echo "ERROR: Failed to copy signing keys"
    ls -la "$TEMP_KEYS_DIR/"
    exit 1
fi

echo "Signing keys loaded successfully"

# Find and sign the module
EVDI_MODULE_PATH=$(find /lib/modules/$(uname -r) -name "evdi.ko" -type f 2>/dev/null | head -1)

if [ -z "$EVDI_MODULE_PATH" ]; then
    echo "ERROR: Could not find installed evdi module"
    echo "Searching for any evdi files:"
    find /lib/modules/$(uname -r) -name "*evdi*" -type f 2>/dev/null || echo "No evdi files found"
    exit 1
fi

echo "Found evdi module at: $EVDI_MODULE_PATH"

# Find the sign-file tool
SIGN_FILE=""
if command -v sign-file >/dev/null 2>&1; then
    SIGN_FILE="sign-file"
elif [ -f "/usr/src/kernels/$(uname -r)/scripts/sign-file" ]; then
    SIGN_FILE="/usr/src/kernels/$(uname -r)/scripts/sign-file"
elif [ -f "/lib/modules/$(uname -r)/source/scripts/sign-file" ]; then
    SIGN_FILE="/lib/modules/$(uname -r)/source/scripts/sign-file"
elif [ -f "/lib/modules/$(uname -r)/build/scripts/sign-file" ]; then
    SIGN_FILE="/lib/modules/$(uname -r)/build/scripts/sign-file"
fi

if [ -z "$SIGN_FILE" ]; then
    echo "ERROR: sign-file tool not found"
    echo "Searching for sign-file:"
    find /usr/src/kernels/$(uname -r) -name "sign-file" -type f 2>/dev/null || echo "Not found in /usr/src/kernels/"
    find /lib/modules/$(uname -r) -name "sign-file" -type f 2>/dev/null || echo "Not found in /lib/modules/"
    exit 1
fi

echo "Using sign-file tool: $SIGN_FILE"
echo "Signing evdi module..."
$SIGN_FILE sha256 "$TEMP_KEYS_DIR/signing_key.pem" "$TEMP_KEYS_DIR/signing_key.x509" "$EVDI_MODULE_PATH"
echo "Module signed successfully"

# Save certificate for MOK enrollment
echo "Setting up MOK certificate..."
mkdir -p /etc/pki/DisplayLink
if [ -f "$SIGNING_KEYS_DIR/evdi-signing-key.der" ]; then
    cp "$SIGNING_KEYS_DIR/evdi-signing-key.der" /etc/pki/DisplayLink/evdi-signing-key.der
else
    # Fallback: convert x509 to DER format
    cp "$TEMP_KEYS_DIR/signing_key.x509" /etc/pki/DisplayLink/evdi-signing-key.der
fi
echo "Certificate saved to /etc/pki/DisplayLink/evdi-signing-key.der"

# Clean up build artifacts
echo "Cleaning up build artifacts..."
cd /
rm -rf /tmp/evdi /tmp/module_signing_keys

# Clean up build dependencies if requested
if [ "$CLEANUP_BUILD_DEPS" = "true" ]; then
    echo "Removing build dependencies..."
    # Remove libdrm-devel as it is not needed after build
    dnf5 -y remove libdrm-devel || echo "libdrm-devel removal failed, continuing..."
fi

# Setup module loading on boot
echo "Setting up module loading on boot..."
mkdir -p /etc/modules-load.d
echo "evdi" > /etc/modules-load.d/evdi.conf
