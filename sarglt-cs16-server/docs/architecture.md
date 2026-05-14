# sarglt-cs16-server — Architecture

This document describes how the sarg.lt CS 1.6 plugin suite fits together: the
runtime layout on the server, the cross-plugin event bus, shared data flow,
and the conventions every plugin must honour. Read this before writing any
plugin code.

It also lists the **open design decisions** that need owner sign-off before
the schema and APIs are frozen. Those are flagged with `[DECISION]` and
collected at the end.

---

## 1. Runtime Layout

Single-host install on Debian 12. The server runs as a non-root user
(`cs16`), with files under `/home/cs16/server/`.

```
/home/cs16/server/
├── hlds_linux                       # ReHLDS binary (32-bit)
├── cstrike/
│   ├── addons/
│   │   ├── metamod/                 # Metamod-R
│   │   │   └── plugins.ini          # loads amxmodx_mm_i386.so
│   │   └── amxmodx/
│   │       ├── plugins/             # compiled .amxx (built from plugins/*)
│   │       ├── configs/
│   │       │   ├── plugins.ini      # AMXX plugin load order
│   │       │   ├── sarglt_*.cfg     # per-plugin config
│   │       │   └── sarglt_secrets.cfg  # DB creds + webhooks (gitignored)
│   │       ├── data/
│   │       │   ├── geoip/           # MaxMind GeoLite2-Country.mmdb
│   │       │   └── lang/            # lt.txt, ru.txt, en.txt (deployed)
│   │       └── logs/
│   ├── maps/
│   └── server.cfg
└── logs/                            # rotated plugin logs
```

The repository in this project mirrors `cstrike/addons/amxmodx/` plus the
SQL, locales, and ops scripts. `scripts/install.sh` lays everything out on
a fresh VPS.

---

## 2. Plugin Layering

Plugins are organised as a small dependency DAG. Lower layers must load
first (controlled by `plugins.ini` order) and higher layers must tolerate
their dependencies being disabled (degrade gracefully + log a warning).

```
┌─────────────────────────────────────────────────────────────────┐
│  Layer 5: Polish      sarglt_hud                                │
├─────────────────────────────────────────────────────────────────┤
│  Layer 4: Game        sarglt_gamemode  sarglt_balance           │
│                       sarglt_reserved  sarglt_mapvote           │
├─────────────────────────────────────────────────────────────────┤
│  Layer 3: Features    sarglt_rtv  sarglt_chat  sarglt_welcome   │
│                       sarglt_stats  sarglt_anticheat            │
│                       sarglt_discord                            │
├─────────────────────────────────────────────────────────────────┤
│  Layer 2: Identity    sarglt_admin   sarglt_vip                 │
├─────────────────────────────────────────────────────────────────┤
│  Layer 1: Foundation  sarglt_core    sarglt_logging             │
└─────────────────────────────────────────────────────────────────┘
```

### Hard vs. soft dependencies

- **Hard**: plugin will refuse to load (or load read-only) without it.
  - Every plugin → `sarglt_core`
  - Every plugin that writes audit data → `sarglt_logging`
  - `sarglt_vip` → `sarglt_admin` (shares the permission check API)
- **Soft**: feature degrades, plugin still works.
  - `sarglt_welcome` works without GeoIP (falls back to English).
  - `sarglt_discord` works without `sockets` module (logs to file only).
  - `sarglt_stats` works without SQL (in-memory session stats only).

---

## 3. `sarglt_core` — The Foundation Plugin

`sarglt_core` is the shared library every other sarglt plugin links against.
It owns four responsibilities:

### 3.1 Event bus

A lightweight publish/subscribe layer built on AMXX `CreateMultiForward` /
`ExecuteForward`. Other plugins register listeners at load time and `core`
fans events out to them. This is the only cross-plugin coupling allowed —
plugins must not call each other's natives directly except through the
APIs `core` exposes.

Defined events (initial set; add as needed):

| Event                              | Payload                                                   |
|------------------------------------|-----------------------------------------------------------|
| `sarglt_player_connected`          | `id`                                                       |
| `sarglt_player_authorized`         | `id, steamid[]`                                            |
| `sarglt_player_disconnected`       | `id, reason[]`                                             |
| `sarglt_player_vip_upgraded`       | `id, old_tier, new_tier`                                   |
| `sarglt_player_vip_expired`        | `id, tier`                                                 |
| `sarglt_player_admin_action`       | `admin_id, target_id, action[], reason[]`                  |
| `sarglt_player_stats_milestone`    | `id, milestone_type, value`                                |
| `sarglt_map_voted`                 | `winning_map[], votes_for, votes_against`                  |
| `sarglt_map_changing`              | `next_map[]`                                               |
| `sarglt_anticheat_detection`       | `id, detector[], severity, evidence_id`                    |
| `sarglt_chat_message`              | `id, channel, message[]`                                   |

Subscribers receive events synchronously on the AMXX thread. Subscribers
must not block; long work (SQL, sockets) goes via the worker pattern
described in §3.4.

### 3.2 Locale loader

`sarglt_core` reads `locales/{lt,ru,en}.txt` at boot and registers them
with the AMXX dictionary system. It also resolves a player's language at
authorize time using GeoIP and caches it on the player slot:

| Country code                   | Language |
|--------------------------------|----------|
| `LT`, `LV`, `EE`               | `lt`     |
| `RU`, `BY`, `UA`, `KZ`         | `ru`     |
| anything else / GeoIP unavailable | `en`  |

Other plugins fetch a player's resolved language via the native
`sarglt_get_lang(id, out[], len)`. They must never re-resolve it themselves.

### 3.3 Player context

Each connected player gets a struct-of-arrays at slot index `id`:

```pawn
g_player_steamid[33][32]
g_player_country[33][3]
g_player_lang[33][3]
g_player_first_seen[33]      // unix timestamp from SQL, 0 if new
g_player_session_started[33] // unix, set on authorize
g_player_flags[33]           // bitfield: AUTHED, VIP, ADMIN, AC_WHITELIST
```

`core` populates this on authorize and clears it on disconnect. Other
plugins read via getter natives. They must not write directly.

### 3.4 SQL worker queue

All SQL goes through `sarglt_core_sql_queue(query[], callback, data[],
len)`. `core` owns the single `SQL_MakeDbTuple` handle and serialises
queries. This (a) keeps connection management in one place, (b) lets us
add tracing / slow-query logging once and have it apply everywhere, and
(c) makes it trivial to swap MariaDB ↔ MySQL ↔ (eventually) PostgreSQL
without touching plugins.

Queries are always parameterised. `core` exposes a small helper that
escapes and quotes values — plugins never concatenate user input into
SQL strings.

---

## 4. Cross-Cutting Concerns

### 4.1 Logging (`sarglt_logging`)

Every plugin logs via `sarglt_log(level, category[], fmt[], ...)`.
`sarglt_logging` writes to:

- `logs/sarglt-YYYY-MM-DD.log` (daily rotated, 30 days retained)
- Optionally to the `audit_log` table for actions that need a durable trail
  (admin actions, bans, VIP grants, anti-cheat detections)

Levels: `DEBUG`, `INFO`, `WARN`, `ERROR`. The active level is controlled by
`sarglt_log_level` cvar; default `INFO` in production, `DEBUG` on the dev
server.

Plugins MUST NOT call `log_amx()` directly. The wrapper guarantees a
consistent format and lets us redirect or sample later without touching
every plugin.

### 4.2 Configuration

Three tiers:

1. **`server.cfg`** — vanilla CS cvars (hostname, sv_lan, etc.).
2. **`amxmodx/configs/sarglt_<plugin>.cfg`** — per-plugin tunables,
   committed to git, safe to share.
3. **`amxmodx/configs/sarglt_secrets.cfg`** — DB creds, Discord webhook
   URLs, anti-cheat replay encryption key. **Gitignored**, deployed by
   `scripts/install.sh` from a template.

Cvars are read once at `plugin_init`, re-read on a `sarglt_reload` admin
command (no server restart needed).

### 4.3 Permission checks

`sarglt_admin` exposes `sarglt_has_flag(id, flag)` and
`sarglt_get_tier(id)`. **Permission checks are never cached across
commands.** Every admin command re-checks on invocation. Caching opens
TOCTOU bugs when admins are demoted mid-session.

### 4.4 Localisation in practice

```pawn
new lang[3];
sarglt_get_lang(id, lang, charsmax(lang));
new msg[192];
formatex(msg, charsmax(msg), "%L", lang, "WELCOME_RETURNING",
         username, days_since);
sarglt_chat_color(id, msg);
```

Lithuanian is the primary locale. The translation discipline (per the
brief) is "feel like a real LT community server, not a literal
translation". When in doubt, the plugin author writes the LT key with a
`# REVIEW` marker and a sarg.lt native speaker signs it off before
release.

### 4.5 Security

- Every chat-triggered command is rate-limited to 1/sec/player in
  `sarglt_core`. Plugins opt in via `sarglt_register_chat_cmd()`.
- All client-supplied strings are validated for length and stripped of
  control characters before SQL or file I/O.
- No `system()`, no `exec()`, no shell-out from Pawn. Period.
- Secrets file is `chmod 600`, owned by `cs16:cs16`.

---

## 5. Plugin Module Contract

Every `sarglt_*` plugin implements:

```pawn
public plugin_init() {
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
    register_cvar("sarglt_<name>_version", PLUGIN_VERSION, FCVAR_SERVER);
    // ... event subscriptions, cvar registration, SQL prepare
}

public plugin_cfg() {
    // exec config + first SQL touch (DB is only safe to query here)
}

public plugin_end() {
    // close handles, flush queues
}
```

Plus, if it owns SQL state:

```pawn
public sarglt_schema_version() { return 1; }
```

`sarglt_core` checks the schema version against the `schema_versions`
table at boot and refuses to load plugins whose expected version is newer
than what's been migrated. This prevents a fresh plugin running against an
old DB.

---

## 6. Data Flow Examples

### 6.1 Player joins

```
client connect
  → ReHLDS  client_connect
  → core    g_player_session_started, queue authorize SQL
  → core    fires sarglt_player_connected
core    on STEAMID resolved (client_authorized)
  → core    populates steamid + country + lang
  → core    SQL upsert into `players`, fetch first_seen + flags
  → core    fires sarglt_player_authorized
  → admin   loads admin flags for this steamid, sets ADMIN bit
  → vip     loads VIP tier + expiration, sets VIP bit
  → welcome shows greeting in player's lang (returning vs first-time)
  → reserved if server full + non-admin/non-VIP: trigger kick logic
  → discord enqueue webhook POST: "player joined"
```

### 6.2 VIP grants VIP

```
admin types: amx_sarglt_vip_grant "STEAM_0:1:..." bronze 30
  → admin   permission check (flag `o`)
  → vip     SQL insert into `vip_grants` + update `vip_status`
  → vip     fires sarglt_player_vip_upgraded
  → logging audit_log row written
  → discord webhook to moderator channel
  → hud     refresh target's HUD if connected
  → chat    notify target in their lang
```

---

## 7. Build & Deploy

- Pawn sources live in `plugins/<name>/<name>.sma`.
- `scripts/update.sh` runs `amxxpc` against each `.sma` and copies the
  `.amxx` into the deployed `addons/amxmodx/plugins/` directory, then
  signals the server (no full restart unless a hard dep changed).
- Server-side compile is preferred over committed `.amxx` binaries —
  Pawn bytecode is per-version and we don't want stale binaries in git.

---

## 8. Open Decisions (`[DECISION]`)

These need owner sign-off before plugin code is written against them.
Each is referenced from the SQL schema or the plugin specs.

1. **`[DECISION-A]` DB engine.** MariaDB 10 vs MySQL 8. Schema is
   compatible across both today. Recommendation: **MariaDB 10.11** —
   simpler Debian packaging, same wire protocol, same SQL surface we
   need.

2. **`[DECISION-B]` Player primary key.** Three options for the
   `players` table:
   - (b1) Synthetic `BIGINT` `player_id`, `steamid` as a unique index.
   - (b2) `steamid VARCHAR(32)` as the PK directly.
   - (b3) Hash of steamid as a `BINARY(8)` PK.
   Recommendation: **(b1)** — keeps FKs narrow, lets us rename a
   steamid in rare edge cases (e.g. Steam ID format changes) without a
   cascade.

3. **`[DECISION-C]` Stats granularity.** Per-weapon stats per player
   per map is `~weapons * maps * players` rows. Recommendation:
   per-weapon per player aggregated (no per-map split for weapons) +
   per-map session summaries. Avoids a 100M-row table on a busy
   server.

4. **`[DECISION-D]` Anti-cheat replay storage.** Replays are bursty
   blobs (10s of view-angles + shots, maybe 5–50 KB compressed). Two
   options:
   - (d1) `MEDIUMBLOB` column in `ac_detections`.
   - (d2) File on disk under `logs/ac/`, only path stored in SQL.
   Recommendation: **(d2)** — keeps the SQL row small, replays are
   rarely read, and rotating old files is simpler than pruning
   blobs.

5. **`[DECISION-E]` Cross-server ban sync.** Today we have one server.
   The schema can either be designed for multi-server now (server_id
   column on bans, optional NULL = global) or kept single-server with a
   migration later. Recommendation: **add `server_id` from day one** —
   nullable, defaults to global. Costs one tinyint and saves a
   migration when the second server lands.

6. **`[DECISION-F]` Anti-cheat thresholds.** The brief explicitly
   leaves these unspecified; they get tuned against real-player data.
   Schema-wise this means thresholds are stored in `ac_config` rows
   keyed by detector name, not hardcoded.

7. **`[DECISION-G]` Per-map vs global rank.** Stats `score` and
   `rank`: global only, or per-map ladders too? Recommendation:
   **global only at v1**, per-map ladders are a view over session data
   if we ever want them.

8. **`[DECISION-H]` VIP gifting cooldown.** Brief says "configurable
   cooldown". Default 7 days between gifts per giver? Schema supports
   it either way; just needs a cvar value.

The schema in `sql/schema.sql` is written assuming the recommended
answer to each of A–H. If any decision flips, the schema migrates
forward rather than being re-issued; we never edit `schema.sql`
in place after the first deploy.
