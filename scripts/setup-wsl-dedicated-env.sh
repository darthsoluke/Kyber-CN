#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
RUNTIME_USER="${KYBER_WSL_RUN_USER:-kyber}"

mkdir -pm755 /etc/apt/keyrings

if ! dpkg --print-foreign-architectures | grep -qx i386; then
  dpkg --add-architecture i386
fi

apt-get update
apt-get install -y \
  apt-transport-https \
  build-essential \
  ca-certificates \
  clang \
  cmake \
  curl \
  dbus-x11 \
  git \
  gnupg2 \
  lib32gcc-s1 \
  lib32stdc++6 \
  libc6-i386 \
  libssl-dev \
  libvulkan1 \
  libvulkan1:i386 \
  mesa-utils \
  mesa-vulkan-drivers \
  mesa-vulkan-drivers:i386 \
  pkg-config \
  protobuf-compiler \
  tar \
  unzip \
  vulkan-tools \
  wget \
  winbind \
  xvfb \
  xz-utils

if [ ! -f /usr/share/keyrings/dart.gpg ]; then
  curl -fsSL https://dl-ssl.google.com/linux/linux_signing_key.pub |
    gpg --dearmor -o /usr/share/keyrings/dart.gpg
fi

cat >/etc/apt/sources.list.d/dart_stable.list <<'EOF'
deb [signed-by=/usr/share/keyrings/dart.gpg arch=amd64] https://storage.googleapis.com/download.dartlang.org/linux/debian stable main
EOF

if [ ! -f /etc/apt/keyrings/winehq-archive.key ]; then
  wget -O /etc/apt/keyrings/winehq-archive.key \
    https://dl.winehq.org/wine-builds/winehq.key
fi

if [ ! -f /etc/apt/sources.list.d/winehq-noble.sources ]; then
  wget -NP /etc/apt/sources.list.d/ \
    https://dl.winehq.org/wine-builds/ubuntu/dists/noble/winehq-noble.sources
fi

apt-get update
apt-get install -y --install-recommends dart winehq-devel

if ! id -u "${RUNTIME_USER}" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "${RUNTIME_USER}"
fi
install -d -m 0755 -o "${RUNTIME_USER}" -g "${RUNTIME_USER}" "/home/${RUNTIME_USER}"

if [ ! -x /root/.cargo/bin/rustc ]; then
  curl https://sh.rustup.rs -sSf |
    sh -s -- -y --default-toolchain nightly-2026-04-06
fi

# shellcheck source=/dev/null
. /root/.cargo/env
rustup toolchain install nightly-2026-04-06
rustup default nightly-2026-04-06

if [ ! -x "/home/${RUNTIME_USER}/wine/bin/wine64" ]; then
  mkdir -p "/home/${RUNTIME_USER}/wine" /tmp/kyber-downloads
  curl -fL \
    https://github.com/GloriousEggroll/wine-ge-custom/releases/download/GE-Proton8-26/wine-lutris-GE-Proton8-26-x86_64.tar.xz \
    -o /tmp/kyber-downloads/wine-ge-custom.tar.xz
  tar -xf /tmp/kyber-downloads/wine-ge-custom.tar.xz \
    -C "/home/${RUNTIME_USER}/wine" \
    --strip-components=1
  chown -R "${RUNTIME_USER}:${RUNTIME_USER}" "/home/${RUNTIME_USER}/wine"
fi

install -d -m 0755 -o "${RUNTIME_USER}" -g "${RUNTIME_USER}" "/home/${RUNTIME_USER}/.local/share/maxima/wine/prefix"

dart --version
rustc --version
cargo --version
"/home/${RUNTIME_USER}/wine/bin/wine64" --version
command -v Xvfb
command -v vulkaninfo
