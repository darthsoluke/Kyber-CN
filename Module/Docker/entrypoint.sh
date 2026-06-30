#!/bin/bash
set -euo pipefail

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "error: required environment variable ${name} is not set" >&2
    exit 64
  fi
}

import_license_if_available() {
  if [[ -z "${KYBER_LICENSE_IMPORT_DIR:-}" ]]; then
    return
  fi

  if [[ ! -d "${KYBER_LICENSE_IMPORT_DIR}" ]]; then
    echo "error: KYBER_LICENSE_IMPORT_DIR does not exist: ${KYBER_LICENSE_IMPORT_DIR}" >&2
    exit 66
  fi

  if [[ ! -f "${KYBER_LICENSE_IMPORT_DIR}/1035052.dlf" ]]; then
    echo "error: BFII license file missing: ${KYBER_LICENSE_IMPORT_DIR}/1035052.dlf" >&2
    exit 66
  fi

  local target_dir="${WINEPREFIX}/drive_c/ProgramData/Electronic Arts/EA Services/License"
  mkdir -p "${target_dir}"
  cp "${KYBER_LICENSE_IMPORT_DIR}/1035052.dlf" "${target_dir}/1035052.dlf"
  if [[ -f "${KYBER_LICENSE_IMPORT_DIR}/1035052_cached.dlf" ]]; then
    cp "${KYBER_LICENSE_IMPORT_DIR}/1035052_cached.dlf" \
      "${target_dir}/1035052_cached.dlf"
  fi

  echo "Imported BFII license into Wine prefix: ${target_dir}"
}

require_env KYBER_GAME_PATH

if [[ ! -f "${KYBER_GAME_PATH}" ]]; then
  echo "error: KYBER_GAME_PATH does not exist: ${KYBER_GAME_PATH}" >&2
  exit 66
fi

# Start XVFB
Xvfb :1 -screen 0 1024x768x16 &

# Set the display for Wine to use the virtual framebuffer
export DISPLAY=:1
export WINEPREFIX="${WINEPREFIX:-/root/.local/share/maxima/wine/prefix}"
mkdir -p "${WINEPREFIX}"
if [[ "${KYBER_PROVISION_LICENSE_ONLY:-0}" != "1" ]]; then
  import_license_if_available
fi

args=(
  ./kyber_cli
  --skip-updates
)

if [[ "${MAXIMA_LOG_LEVEL:-}" == "debug" ]]; then
  args+=(--debug)
fi

if [[ "${KYBER_PROVISION_LICENSE_ONLY:-0}" == "1" ]]; then
  require_env MAXIMA_CREDENTIALS

  echo "Provisioning BFII license into Wine prefix."
  echo "Game: ${KYBER_GAME_PATH}"
  echo "Content ID: ${KYBER_CONTENT_ID:-1035052}"

  args+=(
    provision_license
    --credentials "${MAXIMA_CREDENTIALS}"
    --game-path "${KYBER_GAME_PATH}"
    --content-id "${KYBER_CONTENT_ID:-1035052}"
  )

  exec "${args[@]}"
fi

require_env KYBER_SERVER_NAME
require_env KYBER_SERVER_MAP
require_env KYBER_SERVER_MODE
require_env KYBER_SERVER_PORT
require_env KYBER_SERVER_MAX_PLAYERS
require_env KYBER_MODULE_DIR

if [[ ! -d "${KYBER_MODULE_DIR}" ]]; then
  echo "error: KYBER_MODULE_DIR does not exist: ${KYBER_MODULE_DIR}" >&2
  exit 66
fi

if [[ ! -f "${KYBER_MODULE_DIR}/Kyber.dll" ]]; then
  echo "error: Kyber.dll does not exist under KYBER_MODULE_DIR: ${KYBER_MODULE_DIR}" >&2
  exit 66
fi

if [[ ! -f "${KYBER_MODULE_DIR}/vivoxsdk.dll" ]]; then
  echo "error: vivoxsdk.dll does not exist under KYBER_MODULE_DIR: ${KYBER_MODULE_DIR}" >&2
  exit 66
fi

# Workaround until we can figure out how to edit wine's PATH
cp "${KYBER_MODULE_DIR}/vivoxsdk.dll" "$(dirname "${KYBER_GAME_PATH}")"

args+=(
  start_server
  --server-name "${KYBER_SERVER_NAME}"
  --show-console
  --game-path "${KYBER_GAME_PATH}"
  --module-path "${KYBER_MODULE_DIR}"
  --map "${KYBER_SERVER_MAP}"
  --mode "${KYBER_SERVER_MODE}"
  --server-port "${KYBER_SERVER_PORT}"
  --max-players "${KYBER_SERVER_MAX_PLAYERS}"
  --verbose
)

if [[ "${KYBER_ONLINE_MODE:-0}" == "1" ]]; then
  require_env KYBER_TOKEN
  if [[ -z "${MAXIMA_CREDENTIALS:-}" ]]; then
    echo "error: online BFII host mode requires MAXIMA_CREDENTIALS" >&2
    exit 64
  fi
  args+=(--token "${KYBER_TOKEN}")
else
  args+=(--offline)
fi

if [[ -n "${MAXIMA_CREDENTIALS:-}" ]]; then
  args+=(--credentials="${MAXIMA_CREDENTIALS}")
else
  args+=(--credentialless-host)
fi

echo "Starting KYBER BFII host server named '${KYBER_SERVER_NAME}'"

args+=("$@")

exec "${args[@]}"
