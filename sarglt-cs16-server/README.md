# sarglt-cs16-server

Counter-Strike 1.6 dedicated server stack for the sarg.lt community.

## Stack

- ReHLDS (latest stable)
- ReGameDLL_CS (latest stable)
- Metamod-R (latest stable)
- AMX Mod X 1.10+
- AMXX modules: `engine`, `fakemeta`, `hamsandwich`, `cstrike`, `fun`, `sqlx`, `nvault`, `geoip`, `sockets`
- MySQL 8 / MariaDB 10 (primary persistence)

Target host: Debian 12 (64-bit) running a 32-bit ReHLDS binary, 32 slots.

## Project Layout

```
sarglt-cs16-server/
├── README.md                 # this file
├── INSTALL.md                # end-to-end VPS install (TBD)
├── configs/                  # server.cfg, mapcycle.txt, plugins.ini, ...
├── plugins/                  # all sarglt_* AMXX plugins, one dir each
├── sql/
│   ├── schema.sql            # canonical DB schema
│   ├── migrations/           # forward-only schema migrations
│   └── views.sql             # read-only views for the web frontend (TBD)
├── locales/                  # lt.txt / ru.txt / en.txt
├── scripts/                  # install.sh / update.sh / backup.sh / restart.sh
└── docs/
    ├── architecture.md       # cross-plugin design, event bus, conventions
    ├── plugin_api.md         # internal API for plugin authors (TBD)
    └── admin_commands.md     # admin command reference (TBD)
```

## Conventions

- Plugin prefix: `sarglt_`
- Cvar prefix: `sarglt_`
- Admin command prefix: `amx_sarglt_` (or plain `amx_` for compat)
- Pawn style: 4-space indent, `snake_case` for identifiers
- All user-facing strings live in `locales/{lt,ru,en}.txt` — never hardcoded
- All SQL uses prepared statements via `sqlx`
- All plugins expose a `sarglt_<name>_version` cvar
- All plugins degrade gracefully when SQL / GeoIP / sockets are unavailable

## Build Order

Per the project brief, plugins are built and reviewed incrementally:

1. `sarglt_core` — event bus, locale loader, shared utilities
2. `sarglt_logging`
3. `sarglt_admin`
4. `sarglt_vip`
5. `sarglt_stats`
6. `sarglt_welcome`, `sarglt_chat`
7. `sarglt_rtv`, `sarglt_mapvote`
8. `sarglt_reserved`, `sarglt_balance`
9. `sarglt_anticheat`
10. `sarglt_discord`
11. `sarglt_gamemode`
12. `sarglt_hud`

## Status

Foundation pass. The architecture and SQL schema are drafted; no plugin code
exists yet. See `docs/architecture.md` for the cross-plugin design and the list
of open decisions that need owner sign-off before plugin work begins.
