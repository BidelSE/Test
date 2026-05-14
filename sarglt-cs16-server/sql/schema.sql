-- sarglt-cs16-server — canonical schema (v1)
--
-- Target: MariaDB 10.11 (see DECISION-A in docs/architecture.md).
-- Engine: InnoDB everywhere; we need FKs and row-level locks.
-- Charset: utf8mb4 — players and locales include Lithuanian and Russian text.
--
-- Conventions:
--   * Surrogate BIGINT PKs (DECISION-B / option b1). steamid is a UNIQUE index.
--   * Timestamps are `DATETIME` in UTC. The Pawn side converts to local on
--     display; the DB never stores localised time.
--   * Nullable `server_id` everywhere a row may be cross-server scoped
--     (DECISION-E). NULL means "global / all servers".
--   * No ON DELETE CASCADE on `players` — we soft-delete by clearing flags
--     and keep history rows intact for audit. Other tables cascade where it
--     makes sense (e.g. a deleted ban deletes its audit rows).
--   * `BIGINT UNSIGNED AUTO_INCREMENT` for IDs. Steam IDs are stored as the
--     canonical `STEAM_0:X:NNNNNNN` string in VARCHAR(32).
--
-- Apply order: this file is the v1 baseline. Subsequent changes go in
-- sql/migrations/NNNN_description.sql and are tracked in `schema_versions`.

SET NAMES utf8mb4;
SET time_zone = '+00:00';

-- ---------------------------------------------------------------------------
-- 0. Schema version registry
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS schema_versions (
    plugin       VARCHAR(64) NOT NULL,
    version      INT UNSIGNED NOT NULL,
    applied_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (plugin)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------------
-- 1. Servers (multi-server-ready from day one; DECISION-E)
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS servers (
    server_id    SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
    name         VARCHAR(64) NOT NULL,
    address      VARCHAR(64) NOT NULL,        -- "ip:port"
    region       VARCHAR(8)  NOT NULL DEFAULT 'EU',
    created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (server_id),
    UNIQUE KEY uq_servers_address (address)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------------
-- 2. Players (core identity)
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS players (
    player_id      BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    steamid        VARCHAR(32) NOT NULL,
    last_name      VARCHAR(64) NOT NULL DEFAULT '',
    country        CHAR(2)     NOT NULL DEFAULT '',     -- ISO-3166-1 alpha-2
    lang           CHAR(2)     NOT NULL DEFAULT 'en',   -- resolved at authorize
    first_seen     DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen      DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    total_sessions INT UNSIGNED NOT NULL DEFAULT 0,
    total_seconds  BIGINT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (player_id),
    UNIQUE KEY uq_players_steamid (steamid),
    KEY idx_players_last_seen (last_seen)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS player_names (
    player_id   BIGINT UNSIGNED NOT NULL,
    name        VARCHAR(64) NOT NULL,
    seen_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (player_id, name),
    CONSTRAINT fk_player_names_player
        FOREIGN KEY (player_id) REFERENCES players (player_id)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------------
-- 3. Admin system
-- ---------------------------------------------------------------------------

-- Tier is a denormalised label; the real authority is `flags` (AMXX-style
-- access flag string, e.g. "abcdefghu"). Owner/HeadAdmin/Admin/Moderator/VIP
-- are conventions, not enum values, so adding a new tier later doesn't need
-- a schema change.

CREATE TABLE IF NOT EXISTS admins (
    admin_id     BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    player_id    BIGINT UNSIGNED NULL,            -- NULL if auth_type != steam
    auth_type    ENUM('steam','ip','name') NOT NULL DEFAULT 'steam',
    auth_value   VARCHAR(64) NOT NULL,            -- steamid / ip / "name|password"
    tier         VARCHAR(32) NOT NULL,            -- 'owner','headadmin','admin','moderator','vip'
    flags        VARCHAR(32) NOT NULL,            -- AMXX access flags
    server_id    SMALLINT UNSIGNED NULL,          -- NULL = global
    granted_by   BIGINT UNSIGNED NULL,            -- admin_id of granter, NULL for seed rows
    granted_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at   DATETIME NULL,                   -- NULL = no expiry
    active       TINYINT(1) NOT NULL DEFAULT 1,
    notes        VARCHAR(255) NOT NULL DEFAULT '',
    PRIMARY KEY (admin_id),
    KEY idx_admins_player (player_id),
    KEY idx_admins_auth (auth_type, auth_value),
    KEY idx_admins_server (server_id),
    CONSTRAINT fk_admins_player
        FOREIGN KEY (player_id) REFERENCES players (player_id)
        ON DELETE SET NULL,
    CONSTRAINT fk_admins_server
        FOREIGN KEY (server_id) REFERENCES servers (server_id)
        ON DELETE SET NULL,
    CONSTRAINT fk_admins_granter
        FOREIGN KEY (granted_by) REFERENCES admins (admin_id)
        ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS admin_actions (
    action_id    BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    server_id    SMALLINT UNSIGNED NULL,
    admin_id     BIGINT UNSIGNED NULL,
    admin_name   VARCHAR(64) NOT NULL,   -- snapshot, survives admin delete
    target_id    BIGINT UNSIGNED NULL,   -- nullable: some actions have no target
    target_name  VARCHAR(64) NOT NULL DEFAULT '',
    action       VARCHAR(32) NOT NULL,   -- 'kick','ban','slay','mute','vip_grant','map_change',...
    reason       VARCHAR(255) NOT NULL DEFAULT '',
    metadata     JSON NULL,              -- free-form: duration, weapon, etc.
    created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (action_id),
    KEY idx_aa_admin (admin_id),
    KEY idx_aa_target (target_id),
    KEY idx_aa_action_time (action, created_at),
    CONSTRAINT fk_aa_admin
        FOREIGN KEY (admin_id) REFERENCES admins (admin_id)
        ON DELETE SET NULL,
    CONSTRAINT fk_aa_target
        FOREIGN KEY (target_id) REFERENCES players (player_id)
        ON DELETE SET NULL,
    CONSTRAINT fk_aa_server
        FOREIGN KEY (server_id) REFERENCES servers (server_id)
        ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------------
-- 4. Ban system
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS bans (
    ban_id        BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    server_id     SMALLINT UNSIGNED NULL,                -- NULL = global (cross-server)
    player_id     BIGINT UNSIGNED NULL,                  -- resolved if known
    steamid       VARCHAR(32) NOT NULL,                  -- always present
    ip            VARCHAR(45) NOT NULL DEFAULT '',       -- IPv4/IPv6
    name_snapshot VARCHAR(64) NOT NULL DEFAULT '',
    admin_id      BIGINT UNSIGNED NULL,                  -- NULL = system (auto-ban)
    admin_name    VARCHAR(64) NOT NULL DEFAULT 'SYSTEM',
    reason        VARCHAR(255) NOT NULL,                 -- enforced min 5 chars in plugin
    duration_min  INT UNSIGNED NOT NULL,                 -- 0 = permanent
    created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at    DATETIME NULL,                         -- NULL when permanent
    lifted_at     DATETIME NULL,                         -- NULL until unban
    lifted_by     BIGINT UNSIGNED NULL,
    lift_reason   VARCHAR(255) NOT NULL DEFAULT '',
    appeal_status ENUM('none','pending','accepted','rejected') NOT NULL DEFAULT 'none',
    PRIMARY KEY (ban_id),
    KEY idx_bans_steamid (steamid),
    KEY idx_bans_ip (ip),
    KEY idx_bans_active (lifted_at, expires_at),
    KEY idx_bans_server (server_id),
    CONSTRAINT fk_bans_player
        FOREIGN KEY (player_id) REFERENCES players (player_id)
        ON DELETE SET NULL,
    CONSTRAINT fk_bans_admin
        FOREIGN KEY (admin_id) REFERENCES admins (admin_id)
        ON DELETE SET NULL,
    CONSTRAINT fk_bans_lifted_by
        FOREIGN KEY (lifted_by) REFERENCES admins (admin_id)
        ON DELETE SET NULL,
    CONSTRAINT fk_bans_server
        FOREIGN KEY (server_id) REFERENCES servers (server_id)
        ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS ban_appeals (
    appeal_id    BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    ban_id       BIGINT UNSIGNED NOT NULL,
    submitted_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    contact      VARCHAR(128) NOT NULL DEFAULT '',  -- discord / email
    message      TEXT NOT NULL,
    reviewed_at  DATETIME NULL,
    reviewed_by  BIGINT UNSIGNED NULL,
    decision     ENUM('pending','accepted','rejected') NOT NULL DEFAULT 'pending',
    decision_note VARCHAR(255) NOT NULL DEFAULT '',
    PRIMARY KEY (appeal_id),
    KEY idx_appeals_ban (ban_id),
    CONSTRAINT fk_appeals_ban
        FOREIGN KEY (ban_id) REFERENCES bans (ban_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_appeals_reviewer
        FOREIGN KEY (reviewed_by) REFERENCES admins (admin_id)
        ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Auto-ban triggers: counts kicks/warnings in a sliding window. The plugin
-- queries this with WHERE created_at > NOW() - INTERVAL N MINUTE.
CREATE TABLE IF NOT EXISTS player_warnings (
    warning_id   BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    player_id    BIGINT UNSIGNED NOT NULL,
    server_id    SMALLINT UNSIGNED NULL,
    kind         VARCHAR(32) NOT NULL,   -- 'kick','mute','warn','ac_warn'
    reason       VARCHAR(255) NOT NULL DEFAULT '',
    created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (warning_id),
    KEY idx_pw_player_time (player_id, created_at),
    CONSTRAINT fk_pw_player
        FOREIGN KEY (player_id) REFERENCES players (player_id)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------------
-- 5. VIP system
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS vip_tiers (
    tier         VARCHAR(16) NOT NULL,   -- 'bronze','silver','gold','platinum'
    rank_order   TINYINT UNSIGNED NOT NULL,  -- 1..4, higher = better
    display_tag  VARCHAR(16) NOT NULL,   -- '[VIP]', '[VIP+]', '[VIP++]', '[VIP*]'
    chat_color   CHAR(7) NOT NULL DEFAULT '',  -- e.g. '#FFD700' or AMXX color code
    -- Numeric perks; cvar overrides allowed via sarglt_vip cfg.
    spawn_hp     SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    spawn_armor  SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    spawn_money  INT UNSIGNED NOT NULL DEFAULT 0,
    extra_he     TINYINT UNSIGNED NOT NULL DEFAULT 0,
    extra_flash  TINYINT UNSIGNED NOT NULL DEFAULT 0,
    extra_smoke  TINYINT UNSIGNED NOT NULL DEFAULT 0,
    stats_mult   DECIMAL(3,2) NOT NULL DEFAULT 1.00,
    PRIMARY KEY (tier)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS vip_status (
    player_id    BIGINT UNSIGNED NOT NULL,
    tier         VARCHAR(16) NOT NULL,
    granted_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at   DATETIME NULL,         -- NULL = lifetime
    source       ENUM('admin','payment','gift','promo') NOT NULL DEFAULT 'admin',
    granted_by   BIGINT UNSIGNED NULL,  -- admin_id (or giver's admin_id NULL allowed)
    PRIMARY KEY (player_id),
    CONSTRAINT fk_vs_player
        FOREIGN KEY (player_id) REFERENCES players (player_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_vs_tier
        FOREIGN KEY (tier) REFERENCES vip_tiers (tier)
        ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS vip_grants (
    grant_id     BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    player_id    BIGINT UNSIGNED NOT NULL,
    tier         VARCHAR(16) NOT NULL,
    duration_days INT UNSIGNED NOT NULL,   -- 0 = lifetime
    source       ENUM('admin','payment','gift','promo') NOT NULL,
    granted_by   BIGINT UNSIGNED NULL,
    giver_player_id BIGINT UNSIGNED NULL,  -- set when source='gift'
    note         VARCHAR(255) NOT NULL DEFAULT '',
    created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (grant_id),
    KEY idx_vg_player (player_id),
    KEY idx_vg_giver (giver_player_id, created_at),
    CONSTRAINT fk_vg_player
        FOREIGN KEY (player_id) REFERENCES players (player_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_vg_giver
        FOREIGN KEY (giver_player_id) REFERENCES players (player_id)
        ON DELETE SET NULL,
    CONSTRAINT fk_vg_tier
        FOREIGN KEY (tier) REFERENCES vip_tiers (tier)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Seed the tier table with defaults. Numbers are placeholders — tunable per
-- sarglt_vip.cfg overrides on the server.
INSERT INTO vip_tiers (tier, rank_order, display_tag, chat_color,
                       spawn_hp, spawn_armor, spawn_money,
                       extra_he, extra_flash, extra_smoke, stats_mult)
VALUES
    ('bronze',   1, '[VIP]',   '#CD7F32', 110,   0,  1000, 0, 0, 0, 1.10),
    ('silver',   2, '[VIP+]',  '#C0C0C0', 120,  50,  2000, 1, 0, 0, 1.25),
    ('gold',     3, '[VIP++]', '#FFD700', 130, 100,  4000, 1, 1, 1, 1.50),
    ('platinum', 4, '[VIP*]',  '#E5E4E2', 150, 150,  8000, 2, 2, 1, 2.00)
ON DUPLICATE KEY UPDATE rank_order = VALUES(rank_order);

-- ---------------------------------------------------------------------------
-- 6. Stats system
-- ---------------------------------------------------------------------------

-- Per-player lifetime aggregate. Updated on round end / disconnect.
CREATE TABLE IF NOT EXISTS stats_player (
    player_id     BIGINT UNSIGNED NOT NULL,
    kills         INT UNSIGNED NOT NULL DEFAULT 0,
    deaths        INT UNSIGNED NOT NULL DEFAULT 0,
    headshots     INT UNSIGNED NOT NULL DEFAULT 0,
    shots         INT UNSIGNED NOT NULL DEFAULT 0,
    hits          INT UNSIGNED NOT NULL DEFAULT 0,
    rounds_won    INT UNSIGNED NOT NULL DEFAULT 0,
    rounds_lost   INT UNSIGNED NOT NULL DEFAULT 0,
    bombs_planted INT UNSIGNED NOT NULL DEFAULT 0,
    bombs_defused INT UNSIGNED NOT NULL DEFAULT 0,
    mvps          INT UNSIGNED NOT NULL DEFAULT 0,
    play_seconds  BIGINT UNSIGNED NOT NULL DEFAULT 0,
    score         INT NOT NULL DEFAULT 0,   -- weighted; recomputed by views/job
    last_played   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (player_id),
    KEY idx_stats_score (score),
    CONSTRAINT fk_sp_player
        FOREIGN KEY (player_id) REFERENCES players (player_id)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Per-player per-weapon (DECISION-C: no per-map split here).
CREATE TABLE IF NOT EXISTS stats_weapon (
    player_id    BIGINT UNSIGNED NOT NULL,
    weapon       VARCHAR(24) NOT NULL,   -- 'ak47','m4a1','awp','knife',...
    kills        INT UNSIGNED NOT NULL DEFAULT 0,
    headshots    INT UNSIGNED NOT NULL DEFAULT 0,
    shots        INT UNSIGNED NOT NULL DEFAULT 0,
    hits         INT UNSIGNED NOT NULL DEFAULT 0,
    damage       INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (player_id, weapon),
    CONSTRAINT fk_sw_player
        FOREIGN KEY (player_id) REFERENCES players (player_id)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- One row per session (player on this server from join to disconnect).
CREATE TABLE IF NOT EXISTS stats_sessions (
    session_id    BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    player_id     BIGINT UNSIGNED NOT NULL,
    server_id     SMALLINT UNSIGNED NULL,
    map_name      VARCHAR(64) NOT NULL DEFAULT '',
    started_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ended_at      DATETIME NULL,
    kills         INT UNSIGNED NOT NULL DEFAULT 0,
    deaths        INT UNSIGNED NOT NULL DEFAULT 0,
    headshots     INT UNSIGNED NOT NULL DEFAULT 0,
    rounds_won    INT UNSIGNED NOT NULL DEFAULT 0,
    rounds_lost   INT UNSIGNED NOT NULL DEFAULT 0,
    score         INT NOT NULL DEFAULT 0,
    PRIMARY KEY (session_id),
    KEY idx_ss_player (player_id, started_at),
    KEY idx_ss_map (map_name, started_at),
    CONSTRAINT fk_ss_player
        FOREIGN KEY (player_id) REFERENCES players (player_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_ss_server
        FOREIGN KEY (server_id) REFERENCES servers (server_id)
        ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Monthly hall-of-fame snapshot (filled by a scheduled job; optional feature).
CREATE TABLE IF NOT EXISTS stats_monthly_hof (
    period_yyyymm  INT UNSIGNED NOT NULL,    -- e.g. 202605
    rank_position  SMALLINT UNSIGNED NOT NULL,
    player_id      BIGINT UNSIGNED NOT NULL,
    score          INT NOT NULL,
    kills          INT UNSIGNED NOT NULL,
    deaths         INT UNSIGNED NOT NULL,
    PRIMARY KEY (period_yyyymm, rank_position),
    KEY idx_hof_player (player_id),
    CONSTRAINT fk_hof_player
        FOREIGN KEY (player_id) REFERENCES players (player_id)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------------
-- 7. Anti-cheat
-- ---------------------------------------------------------------------------

-- Detector thresholds live in the DB so admins can tune without recompiles
-- (DECISION-F).
CREATE TABLE IF NOT EXISTS ac_config (
    detector     VARCHAR(32) NOT NULL,    -- 'aimsnap','norecoil','wallshot','speedhack'
    enabled      TINYINT(1) NOT NULL DEFAULT 1,
    warn_at      DECIMAL(8,3) NOT NULL,   -- detector-specific score
    kick_at      DECIMAL(8,3) NOT NULL,
    tempban_at   DECIMAL(8,3) NOT NULL,
    permban_at   DECIMAL(8,3) NULL,       -- NULL = never auto-permban
    tempban_min  INT UNSIGNED NOT NULL DEFAULT 1440,  -- minutes
    notes        VARCHAR(255) NOT NULL DEFAULT '',
    PRIMARY KEY (detector)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Seed the detectors with deliberately permissive thresholds — they MUST be
-- tuned on real data before flipping `enabled` for autoban actions.
INSERT INTO ac_config (detector, enabled, warn_at, kick_at, tempban_at, permban_at, tempban_min, notes)
VALUES
    ('aimsnap',   1, 0.50, 0.80, 0.95, NULL, 1440, 'angle delta per tick beyond human threshold'),
    ('norecoil',  1, 0.60, 0.85, 0.97, NULL, 1440, 'long-run zero-recoil correlation'),
    ('wallshot',  1, 0.70, 0.90, 0.98, NULL, 1440, 'shots through opaque geometry'),
    ('speedhack', 1, 1.05, 1.15, 1.30, 1.50, 1440, 'velocity ratio above engine max')
ON DUPLICATE KEY UPDATE notes = VALUES(notes);

CREATE TABLE IF NOT EXISTS ac_detections (
    detection_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    server_id    SMALLINT UNSIGNED NULL,
    player_id    BIGINT UNSIGNED NOT NULL,
    detector     VARCHAR(32) NOT NULL,
    severity     ENUM('warn','kick','tempban','permban','review') NOT NULL DEFAULT 'review',
    score        DECIMAL(8,3) NOT NULL,
    map_name     VARCHAR(64) NOT NULL DEFAULT '',
    -- DECISION-D: replay lives on disk, only the path lives here.
    replay_path  VARCHAR(255) NOT NULL DEFAULT '',
    summary      VARCHAR(255) NOT NULL DEFAULT '',
    review_state ENUM('open','dismissed','confirmed') NOT NULL DEFAULT 'open',
    reviewed_by  BIGINT UNSIGNED NULL,
    reviewed_at  DATETIME NULL,
    created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (detection_id),
    KEY idx_acd_player_time (player_id, created_at),
    KEY idx_acd_review (review_state, created_at),
    CONSTRAINT fk_acd_player
        FOREIGN KEY (player_id) REFERENCES players (player_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_acd_reviewer
        FOREIGN KEY (reviewed_by) REFERENCES admins (admin_id)
        ON DELETE SET NULL,
    CONSTRAINT fk_acd_server
        FOREIGN KEY (server_id) REFERENCES servers (server_id)
        ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS ac_whitelist (
    player_id    BIGINT UNSIGNED NOT NULL,
    reason       VARCHAR(255) NOT NULL DEFAULT '',
    added_by     BIGINT UNSIGNED NULL,
    added_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (player_id),
    CONSTRAINT fk_acw_player
        FOREIGN KEY (player_id) REFERENCES players (player_id)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------------
-- 8. RTV / map vote history
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS map_votes (
    vote_id      BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    server_id    SMALLINT UNSIGNED NULL,
    started_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ended_at     DATETIME NULL,
    kind         ENUM('rtv','endmap','admin','pre_game','extend') NOT NULL,
    winning_map  VARCHAR(64) NOT NULL DEFAULT '',
    extended     TINYINT(1) NOT NULL DEFAULT 0,
    PRIMARY KEY (vote_id),
    KEY idx_mv_time (started_at),
    CONSTRAINT fk_mv_server
        FOREIGN KEY (server_id) REFERENCES servers (server_id)
        ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS map_vote_choices (
    vote_id      BIGINT UNSIGNED NOT NULL,
    slot         TINYINT UNSIGNED NOT NULL,   -- 1..N
    map_name     VARCHAR(64) NOT NULL,
    votes        SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (vote_id, slot),
    CONSTRAINT fk_mvc_vote
        FOREIGN KEY (vote_id) REFERENCES map_votes (vote_id)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS map_vote_ballots (
    ballot_id    BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    vote_id      BIGINT UNSIGNED NOT NULL,
    player_id    BIGINT UNSIGNED NULL,         -- nullable for guests / unauthed
    map_name     VARCHAR(64) NOT NULL,
    cast_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (ballot_id),
    KEY idx_mvb_vote (vote_id),
    CONSTRAINT fk_mvb_vote
        FOREIGN KEY (vote_id) REFERENCES map_votes (vote_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_mvb_player
        FOREIGN KEY (player_id) REFERENCES players (player_id)
        ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS map_nominations (
    nomination_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    server_id     SMALLINT UNSIGNED NULL,
    player_id     BIGINT UNSIGNED NULL,
    map_name      VARCHAR(64) NOT NULL,
    current_map   VARCHAR(64) NOT NULL DEFAULT '',
    created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (nomination_id),
    KEY idx_mn_current_map (current_map, created_at),
    CONSTRAINT fk_mn_player
        FOREIGN KEY (player_id) REFERENCES players (player_id)
        ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------------
-- 9. Chat log
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS chat_log (
    chat_id      BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    server_id    SMALLINT UNSIGNED NULL,
    player_id    BIGINT UNSIGNED NULL,
    name_snapshot VARCHAR(64) NOT NULL DEFAULT '',
    channel      ENUM('all','team','dead','admin','pm') NOT NULL DEFAULT 'all',
    target_id    BIGINT UNSIGNED NULL,  -- for PMs
    message      VARCHAR(255) NOT NULL,
    created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (chat_id),
    KEY idx_chat_player_time (player_id, created_at),
    KEY idx_chat_time (created_at),
    CONSTRAINT fk_chat_player
        FOREIGN KEY (player_id) REFERENCES players (player_id)
        ON DELETE SET NULL,
    CONSTRAINT fk_chat_target
        FOREIGN KEY (target_id) REFERENCES players (player_id)
        ON DELETE SET NULL,
    CONSTRAINT fk_chat_server
        FOREIGN KEY (server_id) REFERENCES servers (server_id)
        ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------------
-- 10. Reserved-slot kick log
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS reserved_slot_kicks (
    kick_id        BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    server_id      SMALLINT UNSIGNED NULL,
    kicked_player_id  BIGINT UNSIGNED NULL,
    kicked_name    VARCHAR(64) NOT NULL DEFAULT '',
    kicked_ping    SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    replacement_player_id BIGINT UNSIGNED NULL,
    replacement_name VARCHAR(64) NOT NULL DEFAULT '',
    reason         VARCHAR(64) NOT NULL DEFAULT 'reserved_slot',
    created_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (kick_id),
    KEY idx_rsk_time (created_at),
    CONSTRAINT fk_rsk_kicked
        FOREIGN KEY (kicked_player_id) REFERENCES players (player_id)
        ON DELETE SET NULL,
    CONSTRAINT fk_rsk_replacement
        FOREIGN KEY (replacement_player_id) REFERENCES players (player_id)
        ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------------
-- 11. Server message-of-the-day rotation
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS server_motd (
    motd_id      BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    lang         CHAR(2) NOT NULL,
    body         VARCHAR(255) NOT NULL,
    active_from  DATE NULL,
    active_to    DATE NULL,
    enabled      TINYINT(1) NOT NULL DEFAULT 1,
    PRIMARY KEY (motd_id),
    KEY idx_motd_lang (lang, enabled)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------------
-- 12. Generic audit log for cross-cutting events (logging plugin sink)
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS audit_log (
    audit_id     BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    server_id    SMALLINT UNSIGNED NULL,
    plugin       VARCHAR(64) NOT NULL,
    level        ENUM('debug','info','warn','error') NOT NULL DEFAULT 'info',
    category     VARCHAR(64) NOT NULL DEFAULT '',
    actor_player_id  BIGINT UNSIGNED NULL,
    target_player_id BIGINT UNSIGNED NULL,
    message      VARCHAR(255) NOT NULL,
    metadata     JSON NULL,
    created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (audit_id),
    KEY idx_audit_plugin_time (plugin, created_at),
    KEY idx_audit_actor (actor_player_id, created_at),
    CONSTRAINT fk_audit_actor
        FOREIGN KEY (actor_player_id) REFERENCES players (player_id)
        ON DELETE SET NULL,
    CONSTRAINT fk_audit_target
        FOREIGN KEY (target_player_id) REFERENCES players (player_id)
        ON DELETE SET NULL,
    CONSTRAINT fk_audit_server
        FOREIGN KEY (server_id) REFERENCES servers (server_id)
        ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------------
-- Schema version row for this baseline
-- ---------------------------------------------------------------------------

INSERT INTO schema_versions (plugin, version) VALUES ('sarglt_baseline', 1)
ON DUPLICATE KEY UPDATE version = VALUES(version), applied_at = CURRENT_TIMESTAMP;
