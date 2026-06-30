#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CLI_DIR="${ROOT_DIR}/CLI"
DOWNLOAD_DIR="${ROOT_DIR}/.toolchains/downloads"
BUNDLE_BIN="${CLI_DIR}/build/cli/linux_x64/bundle/bin"
WORK_DIR="${CLI_DIR}/_work/wsl-dedicated"
WINE_INJECTOR_SRC="${CLI_DIR}/tools/kyber_wine_injector/kyber_wine_injector.c"

# shellcheck source=/dev/null
. /root/.cargo/env

cd "${CLI_DIR}"

export RUSTFLAGS="-A warnings"

dart pub get

(
  cd rust
  cargo build --release
)

dart build cli -t bin/kyber_cli.dart -o build/cli/linux_x64

mkdir -p "${BUNDLE_BIN}" "${DOWNLOAD_DIR}" "${WORK_DIR}"
cp rust/target/release/librust_lib.so \
  "${BUNDLE_BIN}/librust_lib.so"

curl -fsSL \
  https://s3.kyber.gg/artifacts/github-ci/wine-helper.exe \
  -o "${BUNDLE_BIN}/wine-helper.exe"

x86_64-w64-mingw32-gcc \
  -O2 \
  -municode \
  -Wall \
  -Wextra \
  "${WINE_INJECTOR_SRC}" \
  -o "${BUNDLE_BIN}/kyber-wine-injector.exe"

(
  cd ThirdParty/Maxima
  cargo build --release -p maxima-bootstrap
)

cp ThirdParty/Maxima/target/release/maxima-bootstrap \
  "${BUNDLE_BIN}/maxima-bootstrap"

chmod +x \
  "${BUNDLE_BIN}/kyber_cli" \
  "${BUNDLE_BIN}/librust_lib.so" \
  "${BUNDLE_BIN}/maxima-bootstrap" \
  "${BUNDLE_BIN}/kyber-wine-injector.exe" \
  "${BUNDLE_BIN}/wine-helper.exe"

ls -la "${BUNDLE_BIN}"
