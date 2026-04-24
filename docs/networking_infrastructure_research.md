# Networking Infrastructure Research for Hidden-Information TCG Play

Date: 2026-04-24

## Why this matters for this project

Your current architecture is strongly local/single-process. `main.gd` wires one `ManagerSystemSingleton` to all game events and UI behaviors in one runtime (`action_committed`, `hand_changed`, `board_slot_changed`, etc.). This is great for single-player iteration, but online play needs clear authority boundaries and per-player filtered views of game state. In particular, hidden zones (deck order, hand contents, unrevealed prizes, search results before reveal) cannot be distributed blindly to every client. [See `scenes/main/main.gd`].

## What established games / platforms indicate

### 1) Legends of Runeterra (Riot)
- Riot publicly states LoR is **"game-server authoritative"** in their engineering write-up.
- This is the gold-standard model for competitive hidden-information games: clients submit intents; server validates and applies canonical state.
- Source: Riot engineering article.

### 2) MTG Arena (publicly observable behavior)
- Official support docs are centered around connectivity to Arena servers and service outages.
- While not a full architecture whitepaper, this supports the operational model of an always-online server-backed game.
- Source: Wizards support "Can’t Connect to Server" article.

### 3) Pokémon TCG Live (publicly observable behavior)
- Official support/forum context shows server dependency and recurring battle-log/information-visibility bugs around what should/shouldn’t be shown to the opponent.
- This highlights a core digital TCG challenge: exact public/private information boundaries must be explicit and testable.
- Source: Pokémon community tracked issues + support pages.

### 4) Indie-facing frameworks with explicit hidden-info handling
- **boardgame.io** documents `playerView` and `STRIP_SECRETS`, including language about returning per-player state stripped of hidden information and marking certain secret-manipulating moves server-only.
- **Board Game Arena (developer docs)** explicitly describes sending `_private` notification payloads only to designated players.
- These are very relevant patterns for your project regardless of engine.

## Architecture options for your project

## Option A — Dedicated authoritative game server (recommended target)

### How it works
- Server owns canonical match state and RNG.
- Client sends **commands/intents** only (e.g., `PlayCardFromHand(hand_index=2, target_slot=p0_bench1)`).
- Server validates legality, mutates state, then emits:
  1) **Public event log** (visible to all), and
  2) **Private deltas** per player (only the owning player sees exact hidden details).
- Clients keep local projection for rendering only.

### Pros
- Best hidden-info protection (deck/hand never sent unless rules reveal).
- Best anti-cheat posture (illegal moves rejected centrally).
- Easiest to run ranked/competitive in future.
- Strongest replay/debug potential (server event-sourced history).

### Cons
- Requires operating server infra (even if small VPS at first).
- More engineering upfront (protocol, auth, reconnect, resync).
- Slightly higher perceived latency (usually manageable in turn-based TCG).

### Fit for you
- Best long-term fit if online competitive play is a serious goal.

## Option B — Player-hosted authoritative (listen server)

### How it works
- One client is host authority for a match.
- Other client(s) send commands to host; host resolves and relays.

### Pros
- Very low hosting cost.
- Faster to prototype than full dedicated backend.

### Cons
- Host can inspect/alter all hidden info and state.
- Trust/cheat issues for competitive modes.
- Match stability tied to host quality; host migration complexity.

### Fit for you
- Acceptable only for casual friend matches where trust is assumed.

## Option C — Pure peer-to-peer lockstep with deterministic sim

### How it works
- Each client runs same simulation from same inputs/seed.
- Inputs are exchanged and both sides advance identically.

### Pros
- Minimal server runtime cost.
- Elegant deterministic simulation model.

### Cons
- In hidden-information card games, each client often still needs enough data to stay deterministic, making secrecy difficult.
- High desync/debug complexity.
- Poor cheat resistance unless combined with cryptographic protocols + arbitration server.

### Fit for you
- Generally **not** ideal as primary architecture for competitive hidden-information TCG.

## Option D — Hybrid relay/matchmaking + authoritative micro-match server

### How it works
- Small backend does account/matchmaking/session tokens.
- Match logic runs in lightweight dedicated instances (container or process per match group).

### Pros
- Scales better than monolith.
- Keeps server authority where needed.
- Lets you start small and grow.

### Cons
- Operational complexity higher than single dedicated process.

### Fit for you
- Great medium-term evolution after Option A prototype.

## Recommended direction for this codebase (without implementing networking yet)

To future-proof now, refactor local architecture around **authority-ready boundaries**:

1. **Command layer (intent API)**
   - UI never mutates game state directly.
   - All actions become typed commands with player identity + optional idempotency key.

2. **Pure rules engine**
   - Deterministic `reduce(state, command) -> {new_state, events}`.
   - RNG injected as explicit seed/service, not global randomness.

3. **Visibility projection layer**
   - `project_state_for_player(canonical_state, player_id)` returns filtered view.
   - Include "public-only" transforms for opponent hand/deck as counts/unknown-card placeholders.

4. **Event log as first-class output**
   - Keep public events and private events separate.
   - This is the future network payload and replay source.

5. **Stable card instance IDs everywhere**
   - Needed for reconciliation, logs, reconnect, and reveal transitions.

6. **Deterministic serialization + hash/checkpointing**
   - Periodically hash canonical state for desync diagnostics.

7. **Transport-agnostic match service interface**
   - Define `IMatchAuthority` now with local in-process implementation.
   - Later swap with remote server adapter with minimal gameplay rewrite.

## Practical staged roadmap

### Stage 0 (now, offline)
- Introduce command/event/reducer + projection boundaries in-process.
- Add tests for hidden-info projection (opponent cannot read deck/hand identities).

### Stage 1 (local loopback "server mode")
- Run authority in separate process locally; connect through RPC/WebSocket.
- Keep same protocol you’ll use online.

### Stage 2 (small hosted server)
- Single VPS container with authoritative match service.
- Add reconnect + resync snapshots.

### Stage 3 (production hardening)
- Auth, anti-replay tokens, telemetry, moderation hooks.
- Ranked integrity checks and replay adjudication.

## Decision summary

If you want hidden information to stay truly private and keep competitive integrity, **dedicated authoritative server** is the best foundation. For budget-conscious development, start with a **single small server** and an architecture that already treats clients as untrusted viewers/controllers, not state owners.

P2P/listen-host can be a temporary/casual mode, but it should not be your long-term competitive model.

## Offline development + future online hooks (Option A without external server today)

You can move toward Option A now **without standing up a remote server** by using a local authority adapter pattern:

1. Keep the existing `ManagerSystemSingleton` as the in-process authority for singleplayer/offline.
2. Route scene interactions through a transport-agnostic authority contract (same API whether local or remote).
3. Later replace only the adapter with a networked implementation that forwards commands to a dedicated server.

### Concrete changes to make in this project

- **Add authority interface + local adapter**
  - Introduce a `MatchAuthority` contract and a `LocalMatchAuthority` that forwards to `ManagerSystemSingleton`.
  - Scene code should subscribe to authority signals and submit actions through authority methods, not directly to manager internals.
- **Keep local/offline mode as default**
  - Boot `LocalMatchAuthority` in `_ready()` so all development/testing continues offline.
- **Prepare for hidden-info projection**
  - Keep current local full-state access for now, but start isolating read paths so UI can later consume filtered per-player views from authority.
- **Preserve command boundary**
  - Continue to treat `request_action()` as the mutation gateway; this becomes your future client->server command path.
- **Delay external infra**
  - Add `OnlineMatchAuthority` later; it should match `MatchAuthority` and translate calls to RPC/WebSocket messages.
  - Because scene code already targets `MatchAuthority`, this swap is low-risk.

### Result

This gives you:
- Offline singleplayer unchanged.
- No immediate server setup burden.
- A clear seam for future dedicated-server authority and hidden-information filtering.

## Sources consulted

- Riot Games engineering: *The Legends of Runeterra CI/CD Pipeline* (states LoR is game-server authoritative): https://www.riotgames.com/en/news/legends-runeterra-cicd-pipeline
- MTG Arena support (server connectivity dependency): https://mtgarena-support.wizards.com/hc/en-us/articles/360052758872-Can-t-Connect-to-Server
- Pokémon forums tracked issues (public/private info behavior examples): https://community.pokemon.com/en-us/discussion/13009/pokemon-tcg-live-community-tracked-issues-updated-09-25-25
- Pokémon support (online service account/server context): https://support.pokemon.com/hc/en-us/articles/4406895467668-Pok%C3%A9mon-TCG-Online-Sunset-Information
- boardgame.io secret state docs (`playerView`, `STRIP_SECRETS`, server-only secret moves): https://github.com/boardgameio/boardgame.io/blob/main/docs/documentation/secret-state.md
- Board Game Arena dev docs (`_private` payloads): https://en.doc.boardgamearena.com/Main_game_logic%3A_Game.php
- Photon Fusion topology tradeoffs (cheat protection vs host/shared/dedicated): https://doc.photonengine.com/fusion/current/fusion-choose
- Photon docs on client-authority limitations (PUN not cheat proof): https://doc.photonengine.com/pun/current/gameplay/hackingprotection
