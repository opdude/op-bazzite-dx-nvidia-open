#!/bin/bash

# Script to build EVDI module using Docker with the target Bazzite base image
set -euo pipefail

echo "Building EVDI module using Docker with Bazzite base image..."

BASE_IMAGE="ghcr.io/ublue-os/bazzite-dx-nvidia-open:42"
OUTPUT_DIR="./files/prebuilt-modules"
BUILD_SCRIPT="build-evdi-docker.sh"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Create a temporary build script
cat > "$BUILD_SCRIPT" << 'EOF'
#!/bin/bash
set -euo pipefail

# Install build dependencies
dnf5 -y install kernel-devel kernel-headers git make gcc libdrm-devel

# Get kernel version
KERNEL_VERSION=$(uname -r)
echo "Building for kernel: $KERNEL_VERSION"

# Build the module
cd /tmp
git clone https://github.com/DisplayLink/evdi.git
cd evdi/module

# Build with relaxed compiler flags
export CFLAGS="-Wno-error=sign-compare -Wno-error=missing-field-initializers -Wno-error=discarded-qualifiers -Wno-error"
make CFLAGS="$CFLAGS"

# Copy the built module to output
cp evdi.ko "/output/evdi-${KERNEL_VERSION}.ko"
echo "Module built successfully: evdi-${KERNEL_VERSION}.ko"
EOF

chmod +x "$BUILD_SCRIPT"

# Run the build in Docker
docker run --rm \
    -v "$(pwd)/$OUTPUT_DIR:/output" \
    -v "$(pwd)/$BUILD_SCRIPT:/tmp/build-script.sh" \
    "$BASE_IMAGE" \
    /tmp/build-script.sh

# Clean up
rm "$BUILD_SCRIPT"

echo "EVDI module built successfully and saved to $OUTPUT_DIR"
ls -la "$OUTPUT_DIR"
