# Standalone public server roadmap

This roadmap is for the long-term standalone public server. It must not be
confused with the current BFII host-server path.

## Boundary

Standalone public server means:

- no Battlefront II executable;
- no Maxima/EA launch flow;
- no Denuvo or BFII license file;
- no Kyber.dll injection;
- no Frostbite fixed-address hooks or trampolines.

The current BFII host-server path remains useful for official-style hosting,
but it is a separate product path.

## Keep

These parts can likely remain useful:

- API/proxy/control-plane protocols where they do not assume in-process
  Frostbite state;
- server browser metadata and registration models;
- direct-connect metadata ideas;
- mod manifest and collection validation concepts;
- launcher UX concepts for server configuration.

## Replace

These parts must be replaced for a standalone backend:

- `Module/Source/Core/Main.cpp`: DLL entrypoint becomes a normal server
  executable entrypoint.
- `Module/Source/Core/Program.cpp`: BFII process initialization, MinHook,
  fixed offsets, game hooks, and Frostbite lifecycle are not portable.
- `Module/Source/Core/Server.cpp`: server lifecycle currently delegates to
  Frostbite `Server`, `GameSimulation`, `ServerSpawnInfo`, and player/message
  ABI objects.
- `Module/Public/SDK/*`: these are game-memory layout declarations, not an
  owned server engine API.
- `Module/Public/Core/Memory.h`: Frostbite arena allocation cannot be used.
- `Module/Source/Network/*`: socket utilities may be reusable, but the
  Battlefront II client-compatible protocol/session layer must be owned by the
  standalone server.

## Phase gates

1. Protocol capture and replay proof.
   Capture one vanilla client join path against a BFII host server, document
   packets and state transitions, and replay enough to identify the handshake
   boundary.

2. Minimal lobby/session proof.
   Implement a standalone process that can answer discovery/metadata and reject
   unsupported join attempts with explicit protocol errors.

3. Client-compatible handshake proof.
   Implement enough protocol to let an unmodified client progress past initial
   connection without entering gameplay.

4. Simulation scope decision.
   Choose whether to implement real gameplay simulation, scripted bot-only
   testing, or a control-plane-only relay. Full gameplay simulation is a
   separate engine project.

5. Product split.
   Keep UI labels separate:
   `BFII host server` for the current injected Frostbite path and
   `Standalone server` only for the backend-only implementation.
