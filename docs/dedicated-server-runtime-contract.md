# BFII host-server runtime contract

This contract applies to the game-process BFII host-server path. It is the
official-style 24/7 server path: Battlefront II is launched as a host process
and Kyber is injected into that process. It is not a standalone backend server.

The goal is to make this boundary explicit, testable, and free of hidden
fallbacks.

## Architecture

The BFII host-server startup path follows MVC boundaries:

- Model: immutable launch data such as server name, game path, map, mode, port,
  player count, and online mode.
- Controller: validates and resolves launch data from CLI arguments and
  environment variables. It must not start processes, mutate environment
  variables, or perform network calls.
- View/adapter: CLI command or Docker entrypoint. It displays errors and passes
  validated model data into the runtime startup sequence.

Current implementation points:

- Model: `CLI/lib/models/dedicated_server_launch_config.dart`
- Controller: `CLI/lib/controllers/dedicated_server_launch_controller.dart`
- Mod model: `CLI/lib/models/dedicated_server_mod_config.dart`
- Mod controller: `CLI/lib/controllers/dedicated_server_mod_controller.dart`
- Session model: `CLI/lib/models/dedicated_server_session_config.dart`
- Session controller: `CLI/lib/controllers/dedicated_server_session_controller.dart`
- Auth model: `CLI/lib/models/dedicated_server_auth_context.dart`
- Auth service: `CLI/lib/services/dedicated_server_auth_service.dart`
- License service: `CLI/lib/services/dedicated_server_license_service.dart`
- Mod runtime service: `CLI/lib/services/dedicated_server_mod_runtime_service.dart`
- Game runtime service: `CLI/lib/services/dedicated_server_runtime_service.dart`
- CLI adapter: `CLI/lib/commands/start_server_command.dart`
- Docker adapter: `CLI/docker/entrypoint.sh`

## No fallback rule

No BFII host-server startup layer may silently invent runtime values. Missing or
invalid configuration is an error.

Required values:

- `server-name` or `KYBER_SERVER_NAME`
- `game-path` or `KYBER_GAME_PATH`
- `server-port` or `KYBER_SERVER_PORT`
- `max-players` or `KYBER_SERVER_MAX_PLAYERS`
- `module-path` or `KYBER_MODULE_DIR`
- `map` plus `mode`, or a map rotation source

Map rotation source means either:

- `rotation-file`
- `KYBER_MAP_ROTATION`

`rotation-file` and `KYBER_MAP_ROTATION` are mutually exclusive. A rotation
source must contain at least one playable `mode;map` entry.

Docker host mode additionally requires:

- `KYBER_SERVER_MAP`
- `KYBER_SERVER_MODE`
- `KYBER_SERVER_PORT`
- `KYBER_SERVER_MAX_PLAYERS`

Docker host auth mode is explicit:

- `KYBER_ONLINE_MODE=1` requires both `KYBER_TOKEN` and
  `MAXIMA_CREDENTIALS`.
- Offline/direct mode is the default container mode.
- Offline/direct mode may use `MAXIMA_CREDENTIALS`, or it may set
  `KYBER_CREDENTIALLESS_HOST=1` / pass `--credentialless-host`.
- `KYBER_PROVISION_LICENSE_ONLY=1` is a one-time provisioning action, not a
  host action. It requires `MAXIMA_CREDENTIALS`, `KYBER_GAME_PATH`, and an
  optional `KYBER_CONTENT_ID` defaulting to `1035052`; it must exit after
  writing the BFII license into the current Wine prefix.

Local WSL isolated host mode accepts the same BFII/Maxima credential value via
`KYBER_BFII_HOST_CREDENTIALS`. `KYBER_DEDICATED_CREDENTIALS` remains accepted
as a compatibility alias but should not be used in new documentation.

If no credentials are provided to the WSL one-click host script, it starts in
credentialless offline host mode. That mode disables EA OAuth/login prompts and
passes no Maxima credentials into the CLI. It still launches the BFII/Frostbite
host process, so an already provisioned BFII/Wine runtime state may still be
required by the game itself.

Credentialless WSL/Docker mode requires a license generated for the same
Wine prefix/machine hash. The supported provisioning flow is:

1. Run the one-time provisioning action inside the target WSL/Docker runtime
   with valid EA/Maxima credentials.
2. Confirm it writes `1035052.dlf` under that exact Wine prefix.
3. Start the host later with no credentials via credentialless offline host
   mode.

Importing `1035052.dlf` from another machine or from the Windows host is an
explicit operator action only, via `KYBER_LICENSE_IMPORT_DIR` or
`-LicenseImportDirectory`. It is not automatic, because an imported license is
valid only if the machine hash matches the target Wine prefix. If it does not
match, startup fails before launching BFII with a machine/Wine-prefix mismatch
error. The code must not attempt to bypass Activation/DRM checks.

Mod input sources are mutually exclusive:

- `mod-folder`
- `collection-file` plus `collection-mods-directory`
- `raw-mods`

`collection-file` must not silently use a default mod directory. If it is used,
`collection-mods-directory` must also be explicit.

License sync is explicit:

- If neither `KYBER_LICENSE_ENDPOINT` nor `KYBER_LICENSE_AUTH_TOKEN` is set,
  license sync is disabled.
- If one is set without the other, startup fails.
- If `KYBER_SERVER_METADATA` is set, it must be parseable as comma-separated
  `key=value` entries.

## Unified container paths

The container path contract is:

- Game executable: `KYBER_GAME_PATH`
- Kyber module directory: `KYBER_MODULE_DIR`

The image declares the standard paths, and the entrypoint validates them before
starting:

- `KYBER_GAME_PATH=/mnt/battlefront/starwarsbattlefrontii.exe`
- `KYBER_MODULE_DIR=/root/.local/share/kyber/module`

If those paths are wrong, startup must fail before launching Maxima or the game.

## WSL one-click flow

Provision the target WSL Wine prefix once:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run-wsl-dedicated.ps1 -Action ProvisionLicense -Credentials "persona:password"
```

Start the isolated host after provisioning:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run-wsl-dedicated.ps1 -Action Host
```

Join from a separate BFII client machine:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run-wsl-dedicated.ps1 -Action Join -ServerAddress <wsl-or-public-ip> -ServerPort 25200
```

The `Host` action must not automatically import the Windows host license. If an
operator wants to test license import anyway, they must pass
`-LicenseImportDirectory` explicitly and accept machine-hash mismatch failures
as real errors.

## Error handling

Errors must be surfaced immediately:

- malformed credentials: fail before Maxima/BFII launch;
- missing game executable: fail before Wine/Maxima startup;
- missing module directory: fail before startup;
- invalid port or player count: fail before gRPC setup;
- conflicting online mode flags: fail before login.
- credentialless mode combined with online Kyber registration: fail before
  Maxima startup.
- credentialless mode with a missing, expired, unreadable, or machine-mismatched
  BFII license: fail before BFII launch.

Retries and recovery may be added later only as explicit controller states, not
as implicit fallback branches.
