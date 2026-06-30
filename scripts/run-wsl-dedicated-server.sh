#!/usr/bin/env bash
set -euo pipefail

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "error: required environment variable ${name} is not set" >&2
    exit 64
  fi
}

require_file() {
  local path="$1"
  local label="$2"
  if [[ ! -f "${path}" ]]; then
    echo "error: ${label} does not exist: ${path}" >&2
    exit 66
  fi
}

require_dir() {
  local path="$1"
  local label="$2"
  if [[ ! -d "${path}" ]]; then
    echo "error: ${label} does not exist: ${path}" >&2
    exit 66
  fi
}

append_optional() {
  local name="$1"
  local value="${2:-}"
  if [[ -n "${value}" ]]; then
    args+=("${name}" "${value}")
  fi
}

reexec_as_runtime_user_if_needed() {
  local user="${KYBER_WSL_RUN_USER:-}"
  if [[ -z "${user}" || "$(id -u)" != "0" ]]; then
    return
  fi

  if ! id "${user}" >/dev/null 2>&1; then
    echo "error: KYBER_WSL_RUN_USER does not exist: ${user}" >&2
    exit 66
  fi

  local home_dir
  home_dir="$(getent passwd "${user}" | cut -d: -f6)"
  if [[ -z "${home_dir}" ]]; then
    echo "error: unable to resolve home directory for ${user}" >&2
    exit 66
  fi

  export HOME="${home_dir}"
  export XDG_DATA_HOME="${home_dir}/.local/share"
  mkdir -p "${XDG_DATA_HOME}"
  mkdir -p /tmp/.X11-unix
  if mountpoint -q /tmp/.X11-unix; then
    mount -o remount,rw /tmp/.X11-unix 2>/dev/null || true
  fi
  chmod 1777 /tmp/.X11-unix 2>/dev/null || true
  exec runuser -u "${user}" --preserve-environment -- bash "$0" "$@"
}

import_license_if_available() {
  if [[ -z "${KYBER_LICENSE_IMPORT_DIR:-}" ]]; then
    return
  fi

  require_dir "${KYBER_LICENSE_IMPORT_DIR}" "KYBER_LICENSE_IMPORT_DIR"
  require_file "${KYBER_LICENSE_IMPORT_DIR}/1035052.dlf" "BFII license file"

  local target_dir="${WINEPREFIX}/drive_c/ProgramData/Electronic Arts/EA Services/License"
  mkdir -p "${target_dir}"
  cp "${KYBER_LICENSE_IMPORT_DIR}/1035052.dlf" "${target_dir}/1035052.dlf"
  if [[ -f "${KYBER_LICENSE_IMPORT_DIR}/1035052_cached.dlf" ]]; then
    cp "${KYBER_LICENSE_IMPORT_DIR}/1035052_cached.dlf" \
      "${target_dir}/1035052_cached.dlf"
  fi

  echo "Imported BFII license into Wine prefix: ${target_dir}"
}

restore_cached_license_if_available() {
  local content_id="${KYBER_CONTENT_ID:-1035052}"
  local target_dir="${WINEPREFIX}/drive_c/ProgramData/Electronic Arts/EA Services/License"
  local license_path="${target_dir}/${content_id}.dlf"
  local cached_path="${target_dir}/${content_id}_cached.dlf"

  if [[ -f "${license_path}" || ! -f "${cached_path}" ]]; then
    return
  fi

  cp "${cached_path}" "${license_path}"
  echo "Restored BFII license from cached license: ${license_path}"
}

require_denuvo_token_cache_if_credentialless() {
  if [[ "${KYBER_CREDENTIALLESS_HOST:-1}" != "1" ]]; then
    return
  fi

  if [[ -n "${MAXIMA_DENUVO_TOKEN:-}" || -n "${KYBER_LICENSE_ENDPOINT:-}" ]]; then
    return
  fi

  local content_id="${KYBER_CONTENT_ID:-1035052}"
  local token_path="${WINEPREFIX}/drive_c/ProgramData/Electronic Arts/EA Services/License/${content_id}_denuvo.token"
  require_file "${token_path}" "cached Denuvo token for credentialless host"
}

require_hardware_vulkan_unless_diagnostic() {
  if [[ "${KYBER_ALLOW_SOFTWARE_RENDERER:-0}" == "1" ]]; then
    echo "Warning: KYBER_ALLOW_SOFTWARE_RENDERER=1; skipping hardware Vulkan preflight."
    return
  fi

  if ! command -v vulkaninfo >/dev/null 2>&1; then
    echo "error: vulkaninfo is missing; run scripts/setup-wsl-dedicated-env.sh before hosting." >&2
    exit 70
  fi

  local summary
  summary="$(vulkaninfo --summary 2>&1 || true)"
  if ! grep -Eq 'deviceType[[:space:]]*=[[:space:]]*PHYSICAL_DEVICE_TYPE_(DISCRETE_GPU|INTEGRATED_GPU|VIRTUAL_GPU)' <<<"${summary}"; then
    echo "error: WSL dedicated graphics preflight failed." >&2
    echo "error: BFII host startup requires a hardware Vulkan device for Proton/DXVK." >&2
    echo "error: Current Vulkan summary does not expose a hardware GPU; this usually means only llvmpipe/software rendering is available." >&2
    echo "error: Update WSLg/GPU drivers or use the Windows host path. For diagnostics only, set KYBER_ALLOW_SOFTWARE_RENDERER=1." >&2
    echo "${summary}" | sed -n '1,120p' >&2
    exit 70
  fi
}

ensure_xvfb_display() {
  local server_display="${KYBER_XVFB_DISPLAY}"
  local client_display="${DISPLAY}"
  local screen="${KYBER_XVFB_SCREEN:-1280x720x24}"
  local log_path="/tmp/kyber-dedicated-xvfb-$(id -un).log"

  if [[ ! "${server_display}" =~ ^:[0-9]+(\.[0-9]+)?$ ]]; then
    echo "error: KYBER_XVFB_DISPLAY must be a local X display such as :91, got '${server_display}'" >&2
    exit 64
  fi

  local display_number="${server_display#:}"
  display_number="${display_number%%.*}"
  local socket_path="/tmp/.X11-unix/X${display_number}"
  local lock_path="/tmp/.X${display_number}-lock"

  if pgrep -f "Xvfb ${server_display}([[:space:]]|$)" >/dev/null 2>&1; then
    if [[ -S "${socket_path}" ]]; then
      echo "Using existing Xvfb display ${server_display} for ${client_display} (${screen})."
      return
    fi

    echo "Stopping stale Xvfb display ${server_display} without socket ${socket_path}."
    pgrep -f "Xvfb ${server_display}([[:space:]]|$)" | xargs -r kill 2>/dev/null || true
    sleep 1
  fi

  if [[ -e "${socket_path}" || -e "${lock_path}" ]]; then
    rm -f "${socket_path}" "${lock_path}"
  fi

  rm -f "${log_path}"
  Xvfb "${server_display}" -screen 0 "${screen}" -nolisten tcp -ac >"${log_path}" 2>&1 &
  local xvfb_pid="$!"

  for _ in $(seq 1 40); do
    if ! kill -0 "${xvfb_pid}" 2>/dev/null; then
      echo "error: Xvfb exited while starting display ${server_display}." >&2
      cat "${log_path}" >&2 || true
      exit 70
    fi

    if [[ -S "${socket_path}" ]]; then
      echo "Started Xvfb display ${server_display} for ${client_display} (${screen})."
      return
    fi

    sleep 0.25
  done

  kill "${xvfb_pid}" 2>/dev/null || true
  echo "error: Xvfb did not create ${socket_path} for display ${server_display}." >&2
  cat "${log_path}" >&2 || true
  exit 70
}

reexec_as_runtime_user_if_needed "$@"

export KYBER_BYPASS_DOCKER_I_REALLY_KNOW_WHAT_I_AM_DOING=1
export KYBER_ONLINE_MODE=0
export KYBER_DEDICATED_SERVER=1
export KYBER_DISABLE_SENTRY="${KYBER_DISABLE_SENTRY:-1}"
export KYBER_EARLY_TRACE="${KYBER_EARLY_TRACE:-Z:\\home\\${KYBER_WSL_RUN_USER:-kyber}\\kyber-module-early.log}"
export MAXIMA_DISABLE_QRC=1
export MAXIMA_UMU_GAMEID="${MAXIMA_UMU_GAMEID:-umu-1237950}"
export MAXIMA_WINESTACKSIZE="${MAXIMA_WINESTACKSIZE:-8192}"
export MAXIMA_WINE_INJECTOR_PROCESS_NAME="${MAXIMA_WINE_INJECTOR_PROCESS_NAME:-starwarsbattlefrontii.exe}"
export MAXIMA_WINE_PREFIX_COMMAND="${MAXIMA_WINE_PREFIX_COMMAND:-${XDG_DATA_HOME:-${HOME}/.local/share}/maxima/wine/proton/files/bin/wine}"
export MAXIMA_WINEDLLOVERRIDES="${MAXIMA_WINEDLLOVERRIDES:-CryptBase,wsock32,bcrypt,dxgi,d3d11,d3d12,d3d12core=n,b;winemenubuilder.exe=d}"
export PROTON_USE_XALIA="${PROTON_USE_XALIA:-0}"
if [[ "${KYBER_ALLOW_SOFTWARE_RENDERER:-0}" == "1" ]]; then
  export PROTON_USE_WINED3D="${PROTON_USE_WINED3D:-1}"
else
  unset PROTON_USE_WINED3D
fi
export WINEPREFIX="${WINEPREFIX:-${XDG_DATA_HOME:-${HOME}/.local/share}/maxima/wine/prefix}"
export KYBER_XVFB_DISPLAY="${KYBER_XVFB_DISPLAY:-:91}"
export DISPLAY="${KYBER_DEDICATED_DISPLAY:-${KYBER_XVFB_DISPLAY}}"

ulimit -s 8192 >/dev/null 2>&1 || true

if [[ "${KYBER_SHOW_CONSOLE:-0}" == "1" ]]; then
  unset KYBER_HIDE_CONSOLE
else
  export KYBER_HIDE_CONSOLE=1
fi

require_env KYBER_CLI_BIN
require_env KYBER_GAME_PATH

require_dir "${KYBER_CLI_BIN}" "KYBER_CLI_BIN"
require_file "${KYBER_CLI_BIN}/kyber_cli" "kyber_cli"
require_file "${KYBER_CLI_BIN}/librust_lib.so" "librust_lib.so"
require_file "${KYBER_CLI_BIN}/maxima-bootstrap" "maxima-bootstrap"
require_file "${KYBER_CLI_BIN}/kyber-wine-injector.exe" "kyber-wine-injector.exe"
require_file "${KYBER_CLI_BIN}/wine-helper.exe" "wine-helper.exe"
require_file "${KYBER_GAME_PATH}" "Battlefront II executable"
mkdir -p "${WINEPREFIX}"

cd "${KYBER_CLI_BIN}"

global_args=(./kyber_cli --skip-updates)
if [[ "${MAXIMA_LOG_LEVEL:-}" == "debug" || "${KYBER_DEBUG:-0}" == "1" ]]; then
  global_args+=(--debug)
fi
if [[ "${KYBER_VERBOSE:-1}" == "1" ]]; then
  global_args+=(--verbose)
fi

if [[ "${KYBER_PROVISION_LICENSE_ONLY:-0}" == "1" ]]; then
  require_env MAXIMA_CREDENTIALS

  args=(
    "${global_args[@]}"
    provision_license
    --credentials "${MAXIMA_CREDENTIALS}"
    --game-path "${KYBER_GAME_PATH}"
    --content-id "${KYBER_CONTENT_ID:-1035052}"
  )

  echo "Provisioning BFII license into Wine prefix."
  echo "Game: ${KYBER_GAME_PATH}"
  echo "Content ID: ${KYBER_CONTENT_ID:-1035052}"
  exec "${args[@]}"
fi

require_env KYBER_MODULE_DIR
require_env KYBER_SERVER_NAME
require_env KYBER_SERVER_MAP
require_env KYBER_SERVER_MODE
require_env KYBER_SERVER_PORT
require_env KYBER_SERVER_MAX_PLAYERS
require_env KYBER_SERVER_INTERFACE_PORT

require_dir "${KYBER_MODULE_DIR}" "KYBER_MODULE_DIR"
require_file "${KYBER_MODULE_DIR}/Kyber.dll" "Kyber.dll"
require_file "${KYBER_MODULE_DIR}/vivoxsdk.dll" "vivoxsdk.dll"
import_license_if_available
restore_cached_license_if_available
require_denuvo_token_cache_if_credentialless

ensure_xvfb_display
require_hardware_vulkan_unless_diagnostic

args=(
  "${global_args[@]}"
  start_server
  --offline
  --server-name "${KYBER_SERVER_NAME}"
  --game-path "${KYBER_GAME_PATH}"
  --module-path "${KYBER_MODULE_DIR}"
  --server-port "${KYBER_SERVER_PORT}"
  --max-players "${KYBER_SERVER_MAX_PLAYERS}"
  --map "${KYBER_SERVER_MAP}"
  --mode "${KYBER_SERVER_MODE}"
  --interface-port "${KYBER_SERVER_INTERFACE_PORT}"
)

if [[ -n "${MAXIMA_CREDENTIALS:-}" ]]; then
  args+=(--credentials "${MAXIMA_CREDENTIALS}")
elif [[ "${KYBER_CREDENTIALLESS_HOST:-1}" == "1" ]]; then
  args+=(--credentialless-host)
else
  echo "error: MAXIMA_CREDENTIALS is required unless KYBER_CREDENTIALLESS_HOST=1" >&2
  exit 64
fi

append_optional --server-password "${KYBER_SERVER_PASSWORD:-}"
append_optional --raw-mods "${KYBER_RAW_MODS:-}"
append_optional --collection-file "${KYBER_COLLECTION_FILE:-}"
append_optional --collection-mods-directory "${KYBER_COLLECTION_MODS_DIRECTORY:-}"
append_optional --mod-folder "${KYBER_MOD_FOLDER:-}"
append_optional --startup-commands "${KYBER_STARTUP_COMMANDS:-}"

if [[ -n "${KYBER_GAME_ARGS_FILE:-}" ]]; then
  require_file "${KYBER_GAME_ARGS_FILE}" "KYBER_GAME_ARGS_FILE"
  while IFS= read -r game_arg || [[ -n "${game_arg}" ]]; do
    if [[ -n "${game_arg}" ]]; then
      args+=(--game-args "${game_arg}")
    fi
  done < "${KYBER_GAME_ARGS_FILE}"
fi

echo "Starting isolated Kyber BFII host server."
echo "Game: ${KYBER_GAME_PATH}"
echo "Module: ${KYBER_MODULE_DIR}"
echo "Port: ${KYBER_SERVER_PORT}"
if [[ -n "${MAXIMA_CREDENTIALS:-}" ]]; then
  echo "Auth: EA/Maxima credentials"
else
  echo "Auth: credentialless offline host"
fi

exec "${args[@]}"
