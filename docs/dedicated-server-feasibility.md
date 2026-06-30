# Standalone public server feasibility

This note validates whether the current repository can run a true standalone
public server, meaning a server process that does not launch Battlefront II,
does not depend on Maxima/EA launch flow, and does not inject the Kyber module
into a game process.

## Verdict

The current codebase does not support a standalone public server.

The current server-hosting path is a BFII host-server mode:

1. The CLI starts Battlefront II.
2. The CLI injects `Kyber.dll` into that process.
3. The injected module hooks Frostbite runtime functions.
4. Server creation runs inside the game's `GameSimulation` runtime.

This can still be useful for LAN/direct UDP hosting and 24/7 community-style
hosting, but it is not equivalent to a backend-only Battlefield-style community
server.

Product and UI wording should therefore call this path `BFII host server` or
`game-process host server`, not `standalone dedicated server`.

## Official Kyber dedicated server model

Official Kyber documentation does advertise "Dedicated Servers", but the public
setup path matches the game-process model above, not a standalone simulation
server.

The official Docker run example mounts an installed Battlefront II directory into
the container and passes both EA/Maxima credentials and a Kyber token:

- `MAXIMA_CREDENTIALS=<email>:<password>`
- `KYBER_TOKEN=<token>`
- `-v "<host-install-path>:/mnt/battlefront"`
- `ghcr.io/armchairdevelopers/kyber-server:latest`

The docs also say Battlefront II is required to run Kyber and describe installing
or downloading the game before starting the dedicated server.

The repository Docker image confirms the runtime strategy:

- install Wine and Xvfb-related Linux dependencies;
- copy `Kyber.dll` and supporting module files into the container;
- set `MAXIMA_WINE_COMMAND`;
- run `kyber_cli start_server`;
- pass `--game-path /mnt/battlefront/starwarsbattlefrontii.exe`;
- pass `--credentials` and `--token`.

So the official "dedicated server" is best described as a containerized,
24/7-friendly Battlefront II + Kyber module runtime. It is not evidence that a
separate backend-only Frostbite server executable exists in this repository.

Public joinability comes from online Kyber registration, not from a different
server engine. In online mode, the server registers with the Kyber API/server
browser, clients request join tokens, and the in-game server hook validates
`KyberAuthentication:<token>` through the API before letting the player join.

## Evidence

### Build output is an injected module

`Module/BUILD.bazel` has a single first-party module target:

- `cc_binary(name = "Kyber", ...)`
- `linkshared = 1`

That produces a shared library module, not a standalone server executable.

### CLI always launches the game for server mode

`CLI/lib/commands/start_server_command.dart` sets `KYBER_DEDICATED_SERVER`, then
calls `startGame(...)`, then injects `Kyber.dll` with `injectKyber(...)`.

The important sequence is:

- Set `KYBER_DEDICATED_SERVER`.
- Prepare the gRPC initialize request.
- Launch `star-wars-battlefront-2`.
- Inject `Kyber.dll`.
- Track the game PID as a `MaximaGameInstance`.

This proves the server entrypoint depends on an existing game process.

### Dedicated mode depends on Frostbite in-process runtime

`Module/Source/Core/Program.cpp` reads `KYBER_DEDICATED_SERVER`, but that flag only
changes behavior after the module is already running in the game process.

Dedicated initialization uses game memory and game runtime objects:

- `FB_STATIC_ARENA->alloc(...)`
- `DirtySockSocketManager_ctor(...)`
- `Settings<WSGameSettings>("Whiteshark")`
- `PlatformUtils::HookVTableFunction(...)`
- `GameSimulationSpawnServerHk(...)`

`Program::InitializeGameHooks()` installs hooks at fixed game offsets such as
`OFFSET_GAMESIMULATION_INIT` and `OFFSET_GAMESIMULATION_SPAWNSERVER`.

### Server logic is hook-driven

`Module/Source/Core/Server.cpp` installs separate hook tables for client-hosted
and dedicated modes. Dedicated mode still registers hooks such as:

- `OFFSET_SERVER_CONSTRUCTOR`
- `OFFSET_SERVERCONNECTION_ONCREATEPLAYERMESSAGE`
- `OFFSET_SERVER_UPDATEPASSPREFRAME`
- `ServerLoadLevelMessagePostHk`

These are hooks into the Battlefront II/Frostbite process. They are not a
portable server loop that can be executed by a normal backend binary.

## Feasibility by route

### Route A: true backend-only server using current code

Status: not feasible.

Reason: the core server lifecycle is not owned by Kyber. It is delegated to
Frostbite `GameSimulation`, `Server`, `LevelSetup`, settings, memory arenas, and
DirtySock networking inside the game process.

### Route B: headless Frostbite runtime, if one exists

Status: unknown, worth validating first.

If a legal headless or dedicated Battlefront II/Frostbite runtime exists, Kyber
could target that runtime instead of the normal client executable. This would
still be process-injection or process-hooking, but it could satisfy the user's
"no game client UI" requirement if the runtime is server-only.

Minimum proof:

- Launch the runtime without the normal game client UI.
- Load one multiplayer level.
- Bind the game UDP port.
- Accept one direct/LAN client.
- Run for at least 10 minutes without graphics/UI interaction.

### Route C: custom compatible server implementation

Status: theoretically possible, very large project.

This means implementing enough of the Battlefront II server protocol, state
replication, entity simulation, persistence messages, player lifecycle, map/mode
loading semantics, and mod compatibility outside Frostbite. The current codebase
does not contain enough independent simulation code for this.

This route should be treated as a long-term reverse-engineering/reimplementation
project, not a refactor.

### Route D: BFII host-server mode

Status: already implemented and testable.

This is the current CLI path. It can support LAN/direct public UDP hosting and
can be hardened, automated, and wrapped in service tooling. It still launches
Battlefront II through Maxima/EA/Wine or Windows and injects Kyber, so it does
not meet the standalone-public-server requirement.

## Recommended next gate

Do not start a broad refactor for backend-only dedicated server yet.

First run a phase-0 headless runtime proof:

1. Search the installed game and launch arguments for any server/headless mode.
2. Try launching without renderer/UI while still reaching `GameSimulation`.
3. Verify whether Kyber can inject and hit `LAN_STAGE[dedicated.init.start]`.
4. Verify UDP bind and one client join.

If this proof fails, the honest choices are:

- Continue with game-process dedicated hosting as the near-term public-server
  product.
- Start a separate long-term custom server implementation project.
