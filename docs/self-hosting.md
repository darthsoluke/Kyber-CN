# Kyber self-hosting notes

This repository currently supports two separate hosting paths. Keep them separate when testing.

Self-hosting here means replacing Kyber server registration/proxy routing or bypassing it with direct UDP. It does not currently replace EA/Maxima game launch and login.

The dedicated server path is not a listen server. It still starts the Battlefront II executable as the Frostbite host process, but `KYBER_DEDICATED_SERVER=1` switches the injected Module into server-only mode. The server process must report `dedicated=1`, `runningHosted=0`, and `isLocalHost=0`; a local playable client joining itself is not a valid dedicated-server success condition.

## 1. Direct public hosting without Kyber API registration

This is the practical short-term path for running a community-style dedicated server on your own public machine or VPS. It disables Kyber server registration, proxy routing, and join-token validation, then exposes the game UDP port directly.

Server:

```powershell
$env:KYBER_BYPASS_DOCKER_I_REALLY_KNOW_WHAT_I_AM_DOING="1"
dart run kyber_cli start_server --offline --server-name "Self Hosted Test" --game-path "D:\Games\STAR WARS Battlefront II\starwarsbattlefrontii.exe" --module-path "$env:APPDATA\Kyber\module" --server-port 25200 --map S5_1/Levels/MP/Geonosis_01/Geonosis_01 --mode HeroesVersusVillains
```

Client:

```powershell
dart run kyber_cli start_game --server-address <public-ip-or-hostname> --server-port 25200
```

One-click local wrappers are available under `scripts/`:

- `start-dedicated-server.cmd`: starts the offline dedicated server.
- `join-dedicated-server.cmd`: starts a direct-connect client. Pass `-ServerAddress <ip>` for LAN/public targets.
- `test-dedicated-loopback.cmd`: starts a local dedicated server, waits for `Dedicated server ready`, then starts a local direct-connect client.

The wrappers call `scripts/run-dedicated.ps1` and default to:

- CLI: `CLI/dev_build/cli_bundle/bundle/bin/kyber_cli.exe`
- Module: `CLI/dev_build/module_runtime`
- Game: `D:\Games\STAR WARS Battlefront II\starwarsbattlefrontii.exe`
- Server: `127.0.0.1:25200`

Override values from PowerShell when needed:

```powershell
.\scripts\run-dedicated.ps1 -Action Join -ServerAddress 192.168.1.25 -ServerPort 25200
```

For modded one-click Join/Loopback, use `-RawMods <path-to-raw-mods.json>` so the host and client receive the same mod manifest. The one-click Join/Loopback path deliberately rejects `-ModFolder` and collection-directory options because `start_game` does not support those inputs yet.

Required network setup:

- Open inbound UDP `25200` on the host firewall, cloud firewall, and NAT/router.
- If a custom `--server-port` is used, open that UDP port instead.
- LAN discovery uses UDP `25249`; public direct join does not require discovery broadcast.
- Test with `127.0.0.1` first on one machine, then LAN IP, then public IP/DNS. This separates game startup problems from firewall/NAT problems.

Expected server logs:

- `LAN_STAGE[cli.start_server.mode] onlineMode=false`
- `LAN_STAGE[rpc.launcher.start_server.normalized] onlineMode=0`
- `LAN_STAGE[engine.mainloop.init] dedicated=1`
- `LAN_STAGE[dedicated.registration.skip] reason=offline_lan`
- `LAN_STAGE[dedicated.spawn]`
- `LAN_STAGE[presence.backend.override] ... dedicated=1 ... runningHosted=0`
- `LAN_STAGE[server.ctor.bind_mode] isLocalHost=0 dedicated=1`
- `[Network] Listening on 0.0.0.0:<server-port>`
- `Dedicated server ready: ... port=<server-port>`
- `LAN_STAGE[server.player_join.offline]`

Expected client logs:

- `LAN_STAGE[cli.start_game.direct_join.request]`
- `LAN_STAGE[rpc.launcher.join_server.normalized] onlineMode=0`
- `LAN_STAGE[client.connect.dispatch] mode=direct`

## 2. Self-hosted API and proxy

This path is not the same as direct hosting. It is the path for replacing the official Kyber API/proxy stack so servers can register with your API and clients can join through your proxy list.

Current mandatory services:

- MongoDB, configured with `MONGO_URI`.
- RabbitMQ, configured with `AMQP_URL`.
- EA JWKS endpoint, configured with `EA_JWKS_ENDPOINT`.
- Stable JWT signing keys if more than one API instance or any proxy is used.

Optional services:

- Redis via `REDIS_URI` for caches.
- MinIO via `MINIO_HOST`, `MINIO_ACCESS_KEY`, and `MINIO_SECRET_KEY` for downloads and hosted mod assets.
- Docker auth certificates via `DOCKER_CRT_PATH` and `DOCKER_KEY_PATH`.

Minimum API environment:

```bash
GRPC_PORT=9027
HTTP_PORT=9028
MONGO_URI=mongodb://mongo:27017/kyber
AMQP_URL=amqp://guest:guest@rabbitmq:5672/
EA_JWKS_ENDPOINT=https://example.invalid/ea-jwks.json
WHITELIST_ENABLED=false
KYBER_CONFIG_DIR=/srv/kyber-api/config
JWT_PRIVATE_KEY_PATH=private.pem
JWT_PUBLIC_KEY_PATH=public.pem
JWT_KEY_DIR=/srv/kyber-api/jwt
DOCKER_KEY_DIR=/srv/kyber-api/docker
```

Minimum API config files under `/srv/kyber-api/config`:

- `event-blacklist.yaml`
- `whitelist.yaml`
- `proxies.yaml`

Example files are in `API/config/*.example`.

Minimum proxy environment:

```bash
SERVER_IP=0.0.0.0
SERVER_PORT=8080
JWKS_URL=https://api.example.com/.well-known/jwks.json
```

Compose starter:

```bash
docker compose -f docker-compose.selfhost.yml up --build
```

Before using the compose file for a real public deployment:

- Copy `API/config/proxies.yaml.example` to `API/config/proxies.yaml` and set the proxy `ip` to the public DNS name clients will use. If the proxy is not behind a default `80`/`443` reverse proxy, include `host:port`.
- Match the proxy address scheme with `KYBER_WS_SCHEME`. Use `wss` for TLS reverse proxies and `ws` for plain local/dev deployments.
- Use HTTPS/WSS in production. Plain HTTP/WS is only acceptable for local or private testing.
- Keep stable JWT keys if proxy tokens must survive API restarts or if proxies are started before/independently of the API.
- Expose API gRPC, API HTTP, and proxy WebSocket ports through your reverse proxy/firewall.
- The compose file mounts `./API/jwt` read-only. Either let the API generate ephemeral keys by leaving `JWT_PRIVATE_KEY_PATH` and `JWT_PUBLIC_KEY_PATH` unset, or create the key files before starting compose if you configure those variables.

Client/host environment for a self-host API:

```bash
KYBER_API_HOSTNAME=api-rpc.example.com:9027
KYBER_HTTP_HOSTNAME=api.example.com
KYBER_API_INSECURE=0
KYBER_WS_SCHEME=wss
```

Use `KYBER_API_INSECURE=1` and `KYBER_WS_SCHEME=ws` only for plain HTTP local/dev deployments.

Docker build commands must be run from each component directory with the repository root passed as the `base` build context:

```bash
cd API
docker build --build-context base=../ . -t kyber-api:local

cd ../Proxy
docker build --build-context base=../ . -t kyber-proxy:local
```

## Compatibility requirements

Default behavior should remain official-compatible:

- Without environment overrides, API hosts still resolve to official Kyber endpoints.
- `KYBER_ONLINE_MODE` defaults to online behavior.
- Online server registration still returns `RequiresProxy=true` and hides direct IP/port.
- Offline/direct mode must not request join tokens or register servers.
- Official/self-host WebSocket scheme must be passed to the Module through `KYBER_WS_SCHEME`.

## Known blocker for full proxy replacement

The Module contains a disabled proxied connect branch in `ClientConnectToAddressHk` (`if (false && ... info.isProxied)`). UDP proxy sockets are still initialized through `UDPSocket`, but proxy join behavior needs a dedicated end-to-end test before changing this branch. Do not treat API+Proxy self-hosting as production-ready until official proxy join, self-host proxy join, and direct join are all verified independently.

Recommended current target for a public server is therefore direct public UDP hosting with `--offline`. Use the self-hosted API+Proxy path only as experimental infrastructure work until the proxied client path is enabled and tested.

## Debug stages

Use these markers to isolate failures:

- `LAN_STAGE[cli.start_server.mode]`: CLI parsed online/offline hosting mode.
- `LAN_STAGE[rpc.launcher.start_server.normalized]`: Launcher-to-Module start request was received.
- `LAN_STAGE[server.hook.port.apply]`: Module applied the actual game UDP port.
- `LAN_STAGE[server.registration.skip]`: Direct/offline mode correctly skipped API registration.
- `LAN_STAGE[server.registration.ok]`: Online mode registered with the configured API.
- `LAN_STAGE[proxy.websocket.connect_server]`: Hosted server connected to a proxy.
- `LAN_STAGE[proxy.websocket.connect_client]`: Client connected to a proxy.
- `LAN_STAGE[client.connect.dispatch]`: Client handed final address to the game engine.
- `LAN_STAGE[server.player_join.offline]`: Direct/offline join reached the server.
- `LAN_STAGE[server.player_join.accept]`: Online/proxied join token was accepted.
