/*
 * savekai_elo.sma
 *
 * SAVEKAI ELO system.
 * AMX Mod X 1.10 compatible.
 *
 * Version 0.9 goals:
 * - Every player starts at 1000 ELO.
 * - Players are in placement before normal ELO begins.
 * - ELO is mostly based on round wins/losses.
 * - Team average ELO controls expected score:
 *   Expected = 1 / (1 + 10 ^ ((enemy_avg - own_avg) / 400))
 * - Delta = K * (result - expected)
 * - Small performance modifier adjusts the round delta.
 * - Placement uses weighted target-rating estimates before normal ELO begins.
 * - Softcaps, map/player multipliers, and caps keep changes calm.
 * - Testmode calculates/logs deltas without saving official ELO.
 * - Testmode can still save placement progress so placement testing survives map changes.
 *
 * Player commands:
 * - /elo
 * - /elorank
 * - /rank only if savekai_elo_override_rank 1
 * - /topelo
 * - /session
 * - /elohelp
 *
 * Admin console commands:
 * - amx_elo <player>
 * - amx_setelo <player> <amount>
 * - amx_resetelo <player>
 * - amx_giveelo <player> <amount>
 * - amx_takeelo <player> <amount>
 * - amx_eloreload
 *
 * Required modules:
 * - nvault
 */

#include <amxmodx>
#include <amxmisc>
#include <float>
#include <nvault>

#define PLUGIN_NAME "SAVEKAI ELO"
#define PLUGIN_VERSION "1.8"
#define PLUGIN_AUTHOR "SAVEKAI"

#define MAX_CLIENTS 32
#define AUTH_LEN 40
#define NAME_LEN 32
#define DATA_LEN 256
#define MOTD_LEN 2048
#define TOP_SIZE 10
#define MAX_TRACKED_PLAYERS 2000
#define INVALID_VAULT -1
#define TEAM_T 1
#define TEAM_CT 2
#define TEAM_NONE 0
#define TASK_PROCESS_ROUND 9801
#define ELO_SCALE 100

new g_vault = INVALID_VAULT;

new bool:g_loaded[MAX_CLIENTS + 1];
new g_authid[MAX_CLIENTS + 1][AUTH_LEN];
new g_saved_name[MAX_CLIENTS + 1][NAME_LEN];
new g_elo[MAX_CLIENTS + 1];
new g_elo_cents[MAX_CLIENTS + 1];
new g_ranked_rounds[MAX_CLIENTS + 1];
new g_wins[MAX_CLIENTS + 1];
new g_losses[MAX_CLIENTS + 1];
new g_highest_elo[MAX_CLIENTS + 1];
new g_last_seen[MAX_CLIENTS + 1];
new g_daily_day[MAX_CLIENTS + 1];
new g_daily_gain[MAX_CLIENTS + 1];
new g_daily_gain_cents[MAX_CLIENTS + 1];
new Float:g_placement_target_sum[MAX_CLIENTS + 1];
new Float:g_placement_weight_sum[MAX_CLIENTS + 1];

new g_session_delta[MAX_CLIENTS + 1];
new g_session_gain[MAX_CLIENTS + 1];
new g_session_delta_cents[MAX_CLIENTS + 1];
new g_session_gain_cents[MAX_CLIENTS + 1];
new Float:g_session_placement_target_sum[MAX_CLIENTS + 1];
new Float:g_session_placement_weight_sum[MAX_CLIENTS + 1];
new g_session_rounds[MAX_CLIENTS + 1];
new g_session_wins[MAX_CLIENTS + 1];
new g_session_losses[MAX_CLIENTS + 1];

new bool:g_round_eligible[MAX_CLIENTS + 1];
new g_round_team[MAX_CLIENTS + 1];
new g_round_elo[MAX_CLIENTS + 1];
new g_round_elo_cents[MAX_CLIENTS + 1];
new g_round_kills[MAX_CLIENTS + 1];
new g_round_deaths[MAX_CLIENTS + 1];
new g_round_damage[MAX_CLIENTS + 1];
new g_round_plants[MAX_CLIENTS + 1];
new g_round_defuses[MAX_CLIENTS + 1];
new g_round_teamkills[MAX_CLIENTS + 1];
new g_round_suicides[MAX_CLIENTS + 1];
new g_round_clutch[MAX_CLIENTS + 1];
new bool:g_round_mvp[MAX_CLIENTS + 1];
new bool:g_round_snapshot_valid;
new g_round_winner;
new bool:g_warned_missing_mode_cvar;

new g_slot_count_cache;
new g_slot_authid_cache[MAX_TRACKED_PLAYERS + 1][AUTH_LEN];

new g_clean_name[MAX_CLIENTS + 1][NAME_LEN];
new bool:g_tag_lock[MAX_CLIENTS + 1];

new g_cvar_enabled;
new g_cvar_start;
new g_cvar_placement_enabled;
new g_cvar_placement_rounds;
new g_cvar_placement_min_rounds;
new g_cvar_placement_min_elo;
new g_cvar_placement_max_elo;
new g_cvar_placement_use_performance;
new g_cvar_placement_win_shift;
new g_cvar_placement_loss_shift;
new g_cvar_placement_perf_scale;
new g_cvar_placement_max_above_enemy;
new g_cvar_placement_max_below_enemy;
new g_cvar_placement_weight_multipliers;
new g_cvar_min_leaderboard_rounds;
new g_cvar_k_placement;
new g_cvar_k_provisional;
new g_cvar_provisional_rounds;
new g_cvar_k_normal;
new g_cvar_k_2200;
new g_cvar_k_2400;
new g_cvar_k_2600;
new g_cvar_perf_enabled;
new g_cvar_perf_kill;
new g_cvar_perf_death;
new g_cvar_perf_damage_divisor;
new g_cvar_perf_mvp;
new g_cvar_perf_plant;
new g_cvar_perf_defuse;
new g_cvar_perf_clutch_1v2;
new g_cvar_perf_clutch_1v3;
new g_cvar_perf_clutch_1v4;
new g_cvar_perf_teamkill;
new g_cvar_perf_suicide;
new g_cvar_perf_max_bonus;
new g_cvar_perf_max_penalty;
new g_cvar_perf_carry_protection;
new g_cvar_perf_carry_kills;
new g_cvar_perf_carry_damage;
new g_cvar_perf_carry_loss_cap;
new g_cvar_perf_hardcarry_loss_cap;
new g_cvar_perf_hardcarry_kills;
new g_cvar_perf_hardcarry_damage;
new g_cvar_lost_round_max_delta;
new g_cvar_won_round_min_delta;
new g_cvar_min_players;
new g_cvar_full_players;
new g_cvar_lowplayer_multiplier;
new g_cvar_normal_multiplier;
new g_cvar_arcade_multiplier;
new g_cvar_max_gain_round;
new g_cvar_max_loss_round;
new g_cvar_log_enabled;
new g_cvar_testmode;
new g_cvar_testmode_save_placement;
new g_cvar_disable_non_normal_mode;
new g_cvar_override_rank;
new g_cvar_show_round_delta;
new g_cvar_debug_chat;
new g_cvar_fractional_enabled;
new g_cvar_decimal_display;
new g_cvar_max_team_diff;
new g_cvar_min_team_players;
new g_cvar_uneven_team_mode;
new g_cvar_uneven_team_multiplier;
new g_cvar_uneven_favorite_win_multiplier;
new g_cvar_uneven_underdog_win_multiplier;
new g_cvar_uneven_underdog_loss_multiplier;
new g_cvar_uneven_favorite_loss_multiplier;
new g_cvar_team_size_elo_bonus;
new g_cvar_max_counted_team_diff;
new g_cvar_daily_softcap_enabled;
new g_cvar_daily_softcap_1;
new g_cvar_daily_softcap_2;
new g_cvar_daily_softcap_3;
new g_cvar_daily_mult_1;
new g_cvar_daily_mult_2;
new g_cvar_daily_mult_3;
new g_cvar_daily_mult_4;
new g_cvar_current_mode;
new g_cvar_scoreboard_tags;
new g_cvar_scoreboard_titles_only;
new g_cvar_scoreboard_show_exact;
new g_cvar_season;
new g_cvar_season_name;
new g_cvar_ignore_placement_in_team_avg;
new g_cvar_rated_vs_placement_multiplier;
new g_cvar_min_rated_enemies_for_full_elo;
new g_cvar_placement_default_estimate;

public plugin_init()
{
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
    register_cvar("savekai_elo_version", PLUGIN_VERSION, FCVAR_SERVER);

    g_cvar_enabled = register_cvar("savekai_elo_enabled", "1");
    g_cvar_start = register_cvar("savekai_elo_start", "1000");
    g_cvar_placement_enabled = register_cvar("savekai_elo_placement_enabled", "1");
    g_cvar_placement_rounds = register_cvar("savekai_elo_placement_rounds", "40");
    g_cvar_placement_min_rounds = register_cvar("savekai_elo_placement_min_rounds", "20");
    g_cvar_placement_min_elo = register_cvar("savekai_elo_placement_min_elo", "800");
    g_cvar_placement_max_elo = register_cvar("savekai_elo_placement_max_elo", "2000");
    g_cvar_placement_use_performance = register_cvar("savekai_elo_placement_use_performance", "1");
    g_cvar_placement_win_shift = register_cvar("savekai_elo_placement_win_shift", "220.0");
    g_cvar_placement_loss_shift = register_cvar("savekai_elo_placement_loss_shift", "180.0");
    g_cvar_placement_perf_scale = register_cvar("savekai_elo_placement_perf_scale", "250.0");
    g_cvar_placement_max_above_enemy = register_cvar("savekai_elo_placement_max_above_enemy", "500.0");
    g_cvar_placement_max_below_enemy = register_cvar("savekai_elo_placement_max_below_enemy", "400.0");
    g_cvar_placement_weight_multipliers = register_cvar("savekai_elo_placement_weight_multipliers", "1");
    g_cvar_min_leaderboard_rounds = register_cvar("savekai_elo_min_leaderboard_rounds", "50");
    g_cvar_k_placement = register_cvar("savekai_elo_k_placement", "10.0");
    g_cvar_k_provisional = register_cvar("savekai_elo_k_provisional", "9.0");
    g_cvar_provisional_rounds = register_cvar("savekai_elo_provisional_rounds", "200");
    g_cvar_k_normal = register_cvar("savekai_elo_k_normal", "7.0");
    g_cvar_k_2200 = register_cvar("savekai_elo_k_2200", "5.0");
    g_cvar_k_2400 = register_cvar("savekai_elo_k_2400", "3.5");
    g_cvar_k_2600 = register_cvar("savekai_elo_k_2600", "2.5");
    g_cvar_perf_enabled = register_cvar("savekai_elo_perf_enabled", "1");
    g_cvar_perf_kill = register_cvar("savekai_elo_perf_kill", "0.35");
    g_cvar_perf_death = register_cvar("savekai_elo_perf_death", "-0.25");
    g_cvar_perf_damage_divisor = register_cvar("savekai_elo_perf_damage_divisor", "400.0");
    g_cvar_perf_mvp = register_cvar("savekai_elo_perf_mvp", "0.75");
    g_cvar_perf_plant = register_cvar("savekai_elo_perf_plant", "0.50");
    g_cvar_perf_defuse = register_cvar("savekai_elo_perf_defuse", "1.00");
    g_cvar_perf_clutch_1v2 = register_cvar("savekai_elo_perf_clutch_1v2", "1.00");
    g_cvar_perf_clutch_1v3 = register_cvar("savekai_elo_perf_clutch_1v3", "1.50");
    g_cvar_perf_clutch_1v4 = register_cvar("savekai_elo_perf_clutch_1v4", "2.00");
    g_cvar_perf_teamkill = register_cvar("savekai_elo_perf_teamkill", "-2.00");
    g_cvar_perf_suicide = register_cvar("savekai_elo_perf_suicide", "-1.00");
    g_cvar_perf_max_bonus = register_cvar("savekai_elo_perf_max_bonus", "2.0");
    g_cvar_perf_max_penalty = register_cvar("savekai_elo_perf_max_penalty", "-2.0");
    g_cvar_perf_carry_protection = register_cvar("savekai_elo_perf_carry_protection", "1");
    g_cvar_perf_carry_kills = register_cvar("savekai_elo_perf_carry_kills", "2");
    g_cvar_perf_carry_damage = register_cvar("savekai_elo_perf_carry_damage", "150");
    g_cvar_perf_carry_loss_cap = register_cvar("savekai_elo_perf_carry_loss_cap", "-1");
    g_cvar_perf_hardcarry_loss_cap = register_cvar("savekai_elo_perf_hardcarry_loss_cap", "0");
    g_cvar_perf_hardcarry_kills = register_cvar("savekai_elo_perf_hardcarry_kills", "2");
    g_cvar_perf_hardcarry_damage = register_cvar("savekai_elo_perf_hardcarry_damage", "150");
    g_cvar_lost_round_max_delta = register_cvar("savekai_elo_lost_round_max_delta", "0");
    g_cvar_won_round_min_delta = register_cvar("savekai_elo_won_round_min_delta", "0");
    g_cvar_min_players = register_cvar("savekai_elo_min_players", "4");
    g_cvar_full_players = register_cvar("savekai_elo_full_players", "6");
    g_cvar_lowplayer_multiplier = register_cvar("savekai_elo_lowplayer_multiplier", "0.50");
    g_cvar_normal_multiplier = register_cvar("savekai_elo_normal_multiplier", "1.00");
    g_cvar_arcade_multiplier = register_cvar("savekai_elo_arcade_multiplier", "0.60");
    g_cvar_max_gain_round = register_cvar("savekai_elo_max_gain_round", "6");
    g_cvar_max_loss_round = register_cvar("savekai_elo_max_loss_round", "6");
    g_cvar_log_enabled = register_cvar("savekai_elo_log_enabled", "1");
    g_cvar_testmode = register_cvar("savekai_elo_testmode", "0");
    g_cvar_testmode_save_placement = register_cvar("savekai_elo_testmode_save_placement", "0");
    g_cvar_disable_non_normal_mode = register_cvar("savekai_elo_disable_non_normal_mode", "1");
    g_cvar_override_rank = register_cvar("savekai_elo_override_rank", "0");
    g_cvar_show_round_delta = register_cvar("savekai_elo_show_round_delta", "1");
    g_cvar_debug_chat = register_cvar("savekai_elo_debug_chat", "0");
    g_cvar_fractional_enabled = register_cvar("savekai_elo_fractional_enabled", "1");
    g_cvar_decimal_display = register_cvar("savekai_elo_decimal_display", "1");
    g_cvar_max_team_diff = register_cvar("savekai_elo_max_team_diff", "2");
    g_cvar_min_team_players = register_cvar("savekai_elo_min_team_players", "2");
    g_cvar_uneven_team_mode = register_cvar("savekai_elo_uneven_team_mode", "1");
    g_cvar_uneven_team_multiplier = register_cvar("savekai_elo_uneven_team_multiplier", "0.40");
    g_cvar_uneven_favorite_win_multiplier = register_cvar("savekai_elo_uneven_favorite_win_multiplier", "0.25");
    g_cvar_uneven_underdog_win_multiplier = register_cvar("savekai_elo_uneven_underdog_win_multiplier", "0.85");
    g_cvar_uneven_underdog_loss_multiplier = register_cvar("savekai_elo_uneven_underdog_loss_multiplier", "0.25");
    g_cvar_uneven_favorite_loss_multiplier = register_cvar("savekai_elo_uneven_favorite_loss_multiplier", "1.00");
    g_cvar_team_size_elo_bonus = register_cvar("savekai_elo_team_size_elo_bonus", "150.0");
    g_cvar_max_counted_team_diff = register_cvar("savekai_elo_max_counted_team_diff", "1");
    g_cvar_daily_softcap_enabled = register_cvar("savekai_elo_daily_softcap_enabled", "1");
    g_cvar_daily_softcap_1 = register_cvar("savekai_elo_daily_softcap_1", "50");
    g_cvar_daily_softcap_2 = register_cvar("savekai_elo_daily_softcap_2", "100");
    g_cvar_daily_softcap_3 = register_cvar("savekai_elo_daily_softcap_3", "150");
    g_cvar_daily_mult_1 = register_cvar("savekai_elo_daily_mult_1", "1.00");
    g_cvar_daily_mult_2 = register_cvar("savekai_elo_daily_mult_2", "0.50");
    g_cvar_daily_mult_3 = register_cvar("savekai_elo_daily_mult_3", "0.25");
    g_cvar_daily_mult_4 = register_cvar("savekai_elo_daily_mult_4", "0.10");
    g_cvar_scoreboard_tags = register_cvar("savekai_elo_scoreboard_tags", "1");
    g_cvar_scoreboard_titles_only = register_cvar("savekai_elo_scoreboard_titles_only", "1");
    g_cvar_scoreboard_show_exact = register_cvar("savekai_elo_scoreboard_show_exact", "0");
    g_cvar_season = register_cvar("savekai_elo_season", "0");
    g_cvar_season_name = register_cvar("savekai_elo_season_name", "Season 0 Beta");
    g_cvar_ignore_placement_in_team_avg = register_cvar("savekai_elo_ignore_placement_in_team_avg", "1");
    g_cvar_rated_vs_placement_multiplier = register_cvar("savekai_elo_rated_vs_placement_multiplier", "0.25");
    g_cvar_min_rated_enemies_for_full_elo = register_cvar("savekai_elo_min_rated_enemies_for_full_elo", "2");
    g_cvar_placement_default_estimate = register_cvar("savekai_elo_placement_default_estimate", "1000");

    register_clcmd("say", "hook_say");
    register_clcmd("say_team", "hook_say");

    register_concmd("amx_elo", "concmd_elo", ADMIN_RCON, "<player>");
    register_concmd("amx_setelo", "concmd_setelo", ADMIN_RCON, "<player> <amount>");
    register_concmd("amx_resetelo", "concmd_resetelo", ADMIN_RCON, "<player>");
    register_concmd("amx_giveelo", "concmd_giveelo", ADMIN_RCON, "<player> <amount>");
    register_concmd("amx_takeelo", "concmd_takeelo", ADMIN_RCON, "<player> <amount>");
    register_concmd("amx_eloreload", "concmd_eloreload", ADMIN_RCON, "reload SAVEKAI ELO data");
    register_concmd("amx_elotags_refresh", "concmd_elotags_refresh", ADMIN_RCON, "refresh all SAVEKAI ELO TAB tags");

    register_logevent("logevent_round_start", 2, "1=Round_Start");
    register_logevent("logevent_round_end", 2, "1=Round_End");
    register_logevent("logevent_bomb_planted", 3, "2=Planted_The_Bomb");
    register_logevent("logevent_bomb_defused", 3, "2=Defused_The_Bomb");
    register_event("SendAudio", "event_t_win", "a", "2=%!MRAD_terwin");
    register_event("SendAudio", "event_ct_win", "a", "2=%!MRAD_ctwin");
    register_event("SendAudio", "event_round_draw", "a", "2=%!MRAD_rounddraw");
    register_event("DeathMsg", "event_deathmsg", "a");
    register_event("Damage", "event_damage", "b", "2!0");
}

public plugin_cfg()
{
    g_vault = nvault_open("savekai_elo");

    if (g_vault == INVALID_VAULT)
    {
        log_amx("[SAVEKAI ELO] Failed to open nVault: savekai_elo");
        return;
    }

    g_cvar_current_mode = get_cvar_pointer("savekai_current_mode");
    load_slot_cache();
}

public plugin_end()
{
    remove_task(TASK_PROCESS_ROUND);
    save_all_connected(false);

    if (g_vault != INVALID_VAULT)
    {
        nvault_close(g_vault);
        g_vault = INVALID_VAULT;
    }
}

public client_putinserver(id)
{
    reset_player_memory(id);

    if (!get_pcvar_num(g_cvar_enabled) || is_user_bot(id) || is_user_hltv(id))
    {
        return;
    }

    set_task(8.0, "task_load_player", id);
}

public client_authorized(id)
{
    if (!get_pcvar_num(g_cvar_enabled) || is_user_bot(id) || is_user_hltv(id))
    {
        return;
    }

    remove_task(id);
    load_player(id);
}

public client_disconnected(id)
{
    if (g_round_eligible[id])
    {
        log_round_player_skip_direct(id, "disconnected before round end");
    }

    save_player(id, false);
    remove_task(id);
    reset_round_player(id);
    reset_player_memory(id);
}

public client_infochanged(id)
{
    if (id < 1 || id > MAX_CLIENTS || !is_user_connected(id) || is_user_bot(id) || is_user_hltv(id))
    {
        return;
    }

    if (g_tag_lock[id])
    {
        return;
    }

    new info_name[NAME_LEN];
    get_user_info(id, "name", info_name, charsmax(info_name));
    strip_elo_tags(info_name, charsmax(info_name));

    if (info_name[0] == 0)
    {
        return;
    }

    copy(g_clean_name[id], NAME_LEN - 1, info_name);
    update_scoreboard_tag(id);
}

public concmd_elotags_refresh(id, level, cid)
{
    if (!cmd_access(id, level, cid, 1))
    {
        return PLUGIN_HANDLED;
    }

    refresh_all_scoreboard_tags();
    console_print(id, "[SAVEKAI ELO] Refreshed TAB tags for all connected players.");
    log_admin_change(id, 0, "elotags_refresh", 0, 0, 0);
    return PLUGIN_HANDLED;
}

public task_load_player(id)
{
    if (id < 1 || id > MAX_CLIENTS || !is_user_connected(id))
    {
        return;
    }

    load_player(id);
}

public hook_say(id)
{
    if (!get_pcvar_num(g_cvar_enabled))
    {
        return PLUGIN_CONTINUE;
    }

    new args[96];
    read_args(args, charsmax(args));
    remove_quotes(args);
    trim(args);

    if (is_chat_command(args, "/rank") && !get_pcvar_num(g_cvar_override_rank))
    {
        return PLUGIN_CONTINUE;
    }

    if (is_chat_command(args, "/elo") || is_chat_command(args, "/elorank") || is_chat_command(args, "/rank"))
    {
        return cmd_elo(id);
    }

    if (is_chat_command(args, "/topelo"))
    {
        return cmd_topelo(id);
    }

    if (is_chat_command(args, "/session"))
    {
        return cmd_session(id);
    }

    if (is_chat_command(args, "/elohelp"))
    {
        return cmd_elohelp(id);
    }

    return PLUGIN_CONTINUE;
}

public cmd_elo(id)
{
    if (!ensure_loaded(id))
    {
        client_print(id, print_chat, "[SAVEKAI ELO] Tavo ELO dar neuzkrautas arba authid netinkamas.");
        return PLUGIN_HANDLED;
    }

    print_elo_to_player(id, id);
    return PLUGIN_HANDLED;
}

public cmd_session(id)
{
    new delta_text[16];
    new gain_text[16];
    format_delta_cents(g_session_delta_cents[id], delta_text, charsmax(delta_text));
    format_elo_cents(g_session_gain_cents[id], gain_text, charsmax(gain_text));

    client_print(id, print_chat, "[SAVEKAI ELO] Session: %s ELO | Gain: +%s | Roundai: %d | W/L: %d/%d",
        delta_text,
        gain_text,
        g_session_rounds[id],
        g_session_wins[id],
        g_session_losses[id]
    );

    if (get_pcvar_num(g_cvar_testmode))
    {
        if (get_pcvar_num(g_cvar_testmode_save_placement))
        {
            client_print(id, print_chat, "[SAVEKAI ELO] Test mode: official ELO nesaugomas, placement progress saugomas.");
        }
        else
        {
            client_print(id, print_chat, "[SAVEKAI ELO] Test mode: session rodo skaiciavima, bet ELO nesaugomas.");
        }
    }

    return PLUGIN_HANDLED;
}

public cmd_elohelp(id)
{
    new testmode_text[4];

    if (get_pcvar_num(g_cvar_testmode))
    {
        copy(testmode_text, charsmax(testmode_text), "ON");
    }
    else
    {
        copy(testmode_text, charsmax(testmode_text), "OFF");
    }

    client_print(id, print_chat, "[SAVEKAI ELO] ELO skaiciuojamas pagal round wins/losses + maza performance dali.");
    client_print(id, print_chat, "[SAVEKAI ELO] Stipresnis enemy team = daugiau ELO uz win, maziau prarandi uz loss.");
    client_print(id, print_chat, "[SAVEKAI ELO] Placement: %d roundu, cap %d-%d ELO. Arcade mapai duoda maziau ELO.",
        get_placement_rounds(),
        get_pcvar_num(g_cvar_placement_min_elo),
        get_pcvar_num(g_cvar_placement_max_elo)
    );
    client_print(id, print_chat, "[SAVEKAI ELO] Naudok /elo arba /elorank. /rank lieka default stats, nebent ijungtas override.");
    client_print(id, print_chat, "[SAVEKAI ELO] Minimum real zaideju: %d. Testmode: %s.",
        get_min_players(),
        testmode_text
    );
    return PLUGIN_HANDLED;
}

public cmd_topelo(id)
{
    show_topelo_motd(id);
    return PLUGIN_HANDLED;
}

public concmd_elo(id, level, cid)
{
    if (!cmd_access(id, level, cid, 2))
    {
        return PLUGIN_HANDLED;
    }

    new target_arg[32];
    read_argv(1, target_arg, charsmax(target_arg));

    new target = cmd_target(id, target_arg, CMDTARGET_ALLOW_SELF);

    if (!target || !ensure_loaded(target))
    {
        console_print(id, "[SAVEKAI ELO] Player not found or ELO not loaded.");
        return PLUGIN_HANDLED;
    }

    print_elo_to_console(id, target);
    return PLUGIN_HANDLED;
}

public concmd_setelo(id, level, cid)
{
    if (!cmd_access(id, level, cid, 3))
    {
        return PLUGIN_HANDLED;
    }

    new target = get_admin_target(id, 1);

    if (!target)
    {
        return PLUGIN_HANDLED;
    }

    new amount_arg[16];
    read_argv(2, amount_arg, charsmax(amount_arg));

    new amount = str_to_num(amount_arg);

    if (amount < 0)
    {
        amount = 0;
    }

    set_player_elo_admin(id, target, amount, "set");
    return PLUGIN_HANDLED;
}

public concmd_resetelo(id, level, cid)
{
    if (!cmd_access(id, level, cid, 2))
    {
        return PLUGIN_HANDLED;
    }

    new target = get_admin_target(id, 1);

    if (!target)
    {
        return PLUGIN_HANDLED;
    }

    new old_elo = g_elo[target];
    new start_elo = get_start_elo();
    set_elo_cents(target, elo_to_cents(start_elo));
    g_ranked_rounds[target] = 0;
    g_wins[target] = 0;
    g_losses[target] = 0;
    g_highest_elo[target] = start_elo;
    g_daily_day[target] = get_current_day();
    g_daily_gain[target] = 0;
    g_daily_gain_cents[target] = 0;
    g_placement_target_sum[target] = 0.0;
    g_placement_weight_sum[target] = 0.0;
    g_session_delta[target] = 0;
    g_session_gain[target] = 0;
    g_session_delta_cents[target] = 0;
    g_session_gain_cents[target] = 0;
    g_session_placement_target_sum[target] = 0.0;
    g_session_placement_weight_sum[target] = 0.0;
    g_session_rounds[target] = 0;
    g_session_wins[target] = 0;
    g_session_losses[target] = 0;

    save_player(target, true);
    update_scoreboard_tag(target);
    announce_admin_change(id, target, "reset", old_elo, start_elo);
    return PLUGIN_HANDLED;
}

public concmd_giveelo(id, level, cid)
{
    if (!cmd_access(id, level, cid, 3))
    {
        return PLUGIN_HANDLED;
    }

    new target = get_admin_target(id, 1);

    if (!target)
    {
        return PLUGIN_HANDLED;
    }

    new amount_arg[16];
    read_argv(2, amount_arg, charsmax(amount_arg));

    new amount = abs(str_to_num(amount_arg));
    set_player_elo_admin(id, target, g_elo[target] + amount, "give");
    return PLUGIN_HANDLED;
}

public concmd_takeelo(id, level, cid)
{
    if (!cmd_access(id, level, cid, 3))
    {
        return PLUGIN_HANDLED;
    }

    new target = get_admin_target(id, 1);

    if (!target)
    {
        return PLUGIN_HANDLED;
    }

    new amount_arg[16];
    read_argv(2, amount_arg, charsmax(amount_arg));

    new amount = abs(str_to_num(amount_arg));
    new new_elo = g_elo[target] - amount;

    if (new_elo < 0)
    {
        new_elo = 0;
    }

    set_player_elo_admin(id, target, new_elo, "take");
    return PLUGIN_HANDLED;
}

public concmd_eloreload(id, level, cid)
{
    if (!cmd_access(id, level, cid, 1))
    {
        return PLUGIN_HANDLED;
    }

    load_slot_cache();

    for (new player = 1; player <= MAX_CLIENTS; player++)
    {
        if (is_user_connected(player) && !is_user_bot(player) && !is_user_hltv(player))
        {
            load_player(player);
        }
    }

    refresh_all_scoreboard_tags();
    console_print(id, "[SAVEKAI ELO] Reloaded ELO data for connected players.");
    log_admin_change(id, 0, "reload", 0, 0, 0);
    return PLUGIN_HANDLED;
}

public event_t_win()
{
    g_round_winner = TEAM_T;
    log_winner_detected("T");
}

public event_ct_win()
{
    g_round_winner = TEAM_CT;
    log_winner_detected("CT");
}

public event_round_draw()
{
    g_round_winner = TEAM_NONE;
    log_winner_detected("DRAW");
}

public event_deathmsg()
{
    new attacker = read_data(1);
    new victim = read_data(2);

    if (victim >= 1 && victim <= MAX_CLIENTS && g_round_eligible[victim])
    {
        g_round_deaths[victim]++;
    }

    if (attacker < 1 || attacker > MAX_CLIENTS || !g_round_eligible[attacker])
    {
        return;
    }

    if (attacker == victim)
    {
        g_round_suicides[attacker]++;
        return;
    }

    if (victim < 1 || victim > MAX_CLIENTS)
    {
        return;
    }

    new attacker_team = get_user_team(attacker);
    new victim_team = get_user_team(victim);

    if (attacker_team != TEAM_T && attacker_team != TEAM_CT)
    {
        return;
    }

    if (victim_team != TEAM_T && victim_team != TEAM_CT)
    {
        return;
    }

    if (attacker_team == victim_team)
    {
        g_round_teamkills[attacker]++;
        return;
    }

    update_clutch_state(attacker, attacker_team, victim_team);
    g_round_kills[attacker]++;
}

public event_damage(victim)
{
    if (victim < 1 || victim > MAX_CLIENTS || !g_round_eligible[victim])
    {
        return;
    }

    new attacker = get_user_attacker(victim);

    if (attacker < 1 || attacker > MAX_CLIENTS || attacker == victim || !g_round_eligible[attacker])
    {
        return;
    }

    new attacker_team = get_user_team(attacker);
    new victim_team = get_user_team(victim);

    if ((attacker_team != TEAM_T && attacker_team != TEAM_CT) ||
        (victim_team != TEAM_T && victim_team != TEAM_CT) ||
        attacker_team == victim_team)
    {
        return;
    }

    new damage = read_data(2);

    if (damage > 0)
    {
        g_round_damage[attacker] += damage;
    }
}

public logevent_bomb_planted()
{
    new id = get_logevent_player();

    if (id >= 1 && id <= MAX_CLIENTS && g_round_eligible[id])
    {
        g_round_plants[id]++;
    }
}

public logevent_bomb_defused()
{
    new id = get_logevent_player();

    if (id >= 1 && id <= MAX_CLIENTS && g_round_eligible[id])
    {
        g_round_defuses[id]++;
    }
}

public logevent_round_start()
{
    remove_task(TASK_PROCESS_ROUND);
    snapshot_round_players();
}

public logevent_round_end()
{
    remove_task(TASK_PROCESS_ROUND);
    set_task(0.3, "task_process_round_elo", TASK_PROCESS_ROUND);
}

public task_process_round_elo()
{
    process_round_elo();
}

stock snapshot_round_players()
{
    reset_round_snapshot();

    if (!get_pcvar_num(g_cvar_enabled))
    {
        return;
    }

    if (get_pcvar_num(g_cvar_disable_non_normal_mode) && get_savekai_current_mode() != 0)
    {
        log_elo_round_skip("round start skipped: non-normal mode");
        return;
    }

    new players[32], count;
    get_players(players, count, "ch");

    for (new i = 0; i < count; i++)
    {
        new id = players[i];
        new team = get_user_team(id);

        if (team != TEAM_T && team != TEAM_CT)
        {
            continue;
        }

        if (!ensure_loaded(id))
        {
            continue;
        }

        g_round_eligible[id] = true;
        g_round_team[id] = team;
        g_round_elo[id] = g_elo[id];
        g_round_elo_cents[id] = g_elo_cents[id];
    }

    g_round_snapshot_valid = true;
    log_round_snapshot();
}

stock process_round_elo()
{
    if (!get_pcvar_num(g_cvar_enabled) || !g_round_snapshot_valid)
    {
        log_elo_round_skip("no valid round snapshot");
        reset_round_snapshot();
        return;
    }

    if (get_pcvar_num(g_cvar_disable_non_normal_mode) && get_savekai_current_mode() != 0)
    {
        log_elo_round_skip("non-normal mode");
        reset_round_snapshot();
        return;
    }

    if (g_round_winner != TEAM_T && g_round_winner != TEAM_CT)
    {
        log_elo_round_skip("draw/no winner");
        reset_round_snapshot();
        return;
    }

    new t_count, ct_count, total_count;
    new t_sum_cents, ct_sum_cents;
    new t_rated_count, ct_rated_count;
    new t_rated_sum_cents, ct_rated_sum_cents;

    for (new id = 1; id <= MAX_CLIENTS; id++)
    {
        if (!is_round_player_valid(id))
        {
            log_round_player_skip_if_needed(id);
            continue;
        }

        total_count++;

        new bool:player_rated = !is_in_placement(id);

        if (g_round_team[id] == TEAM_T)
        {
            t_count++;
            t_sum_cents += g_round_elo_cents[id];

            if (player_rated)
            {
                t_rated_count++;
                t_rated_sum_cents += g_round_elo_cents[id];
            }
        }
        else if (g_round_team[id] == TEAM_CT)
        {
            ct_count++;
            ct_sum_cents += g_round_elo_cents[id];

            if (player_rated)
            {
                ct_rated_count++;
                ct_rated_sum_cents += g_round_elo_cents[id];
            }
        }
    }

    if (total_count < get_min_players() || t_count <= 0 || ct_count <= 0)
    {
        log_elo_round_skip("too few players or empty team");
        reset_round_snapshot();
        return;
    }

    if (t_count < get_min_team_players() || ct_count < get_min_team_players())
    {
        log_elo_round_skip("too few players on one team");
        reset_round_snapshot();
        return;
    }

    new team_diff = abs(t_count - ct_count);
    new max_counted_team_diff = get_max_counted_team_diff();

    if (team_diff > 0 && !get_pcvar_num(g_cvar_uneven_team_mode))
    {
        log_elo_round_skip("uneven teams disabled");
        reset_round_snapshot();
        return;
    }

    if (max_counted_team_diff >= 0 && team_diff > max_counted_team_diff)
    {
        log_elo_round_skip("team size difference too high");
        reset_round_snapshot();
        return;
    }

    new Float:t_avg = float(t_sum_cents) / float(ELO_SCALE) / float(t_count);
    new Float:ct_avg = float(ct_sum_cents) / float(ELO_SCALE) / float(ct_count);
    new bool:ignore_placement_avg = get_pcvar_num(g_cvar_ignore_placement_in_team_avg) != 0;
    new Float:default_estimate = float(get_pcvar_num(g_cvar_placement_default_estimate));
    new Float:t_rated_avg = t_rated_count > 0 ? (float(t_rated_sum_cents) / float(ELO_SCALE) / float(t_rated_count)) : default_estimate;
    new Float:ct_rated_avg = ct_rated_count > 0 ? (float(ct_rated_sum_cents) / float(ELO_SCALE) / float(ct_rated_count)) : default_estimate;
    new Float:placement_t_avg = t_avg;
    new Float:placement_ct_avg = ct_avg;
    new placement_ignored_count = (t_count - t_rated_count) + (ct_count - ct_rated_count);
    new Float:effective_t_avg = ignore_placement_avg ? t_rated_avg : t_avg;
    new Float:effective_ct_avg = ignore_placement_avg ? ct_rated_avg : ct_avg;
    new Float:map_multiplier = get_map_multiplier();
    new Float:player_multiplier = get_player_count_multiplier(total_count);
    new Float:uneven_multiplier = get_uneven_team_multiplier(team_diff);
    new Float:size_bonus_applied = apply_team_size_bonus(t_count, ct_count, effective_t_avg, effective_ct_avg);
    new bool:testmode = get_pcvar_num(g_cvar_testmode) != 0;
    new winner_text[4];

    if (g_round_winner == TEAM_T)
    {
        copy(winner_text, charsmax(winner_text), "T");
    }
    else
    {
        copy(winner_text, charsmax(winner_text), "CT");
    }

    new map_name[32];
    new season_name[48];
    get_mapname(map_name, charsmax(map_name));
    get_pcvar_string(g_cvar_season_name, season_name, charsmax(season_name));
    sanitize_name(season_name, charsmax(season_name));

    if (get_pcvar_num(g_cvar_log_enabled))
    {
        log_to_file("savekai_elo.log",
            "Round season=%d season_name=%s map=%s mode=%d winner=%s total=%d T=%d CT=%d team_size_diff=%d T_avg=%.1f CT_avg=%.1f effective_T_avg=%.1f effective_CT_avg=%.1f map_mult=%.2f player_mult=%.2f uneven_mult=%.2f team_size_bonus=%.1f testmode=%d T_rated=%d CT_rated=%d placement_players_ignored=%d ignore_placement=%d rated_default_estimate=%.0f",
            get_pcvar_num(g_cvar_season),
            season_name,
            map_name,
            get_savekai_current_mode(),
            winner_text,
            total_count,
            t_count,
            ct_count,
            team_diff,
            t_avg,
            ct_avg,
            effective_t_avg,
            effective_ct_avg,
            map_multiplier,
            player_multiplier,
            uneven_multiplier,
            size_bonus_applied,
            testmode ? 1 : 0,
            t_rated_count,
            ct_rated_count,
            placement_ignored_count,
            ignore_placement_avg ? 1 : 0,
            default_estimate
        );
    }

    mark_round_mvp();

    for (new id = 1; id <= MAX_CLIENTS; id++)
    {
        if (!is_round_player_valid(id))
        {
            continue;
        }

        apply_round_delta(id, effective_t_avg, effective_ct_avg, map_multiplier, player_multiplier, testmode, t_count, ct_count, team_diff, t_rated_count, ct_rated_count, placement_ignored_count, placement_t_avg, placement_ct_avg);
    }

    reset_round_snapshot();
}

stock apply_round_delta(id, Float:t_avg, Float:ct_avg, Float:map_multiplier, Float:player_multiplier, bool:testmode, t_count, ct_count, team_diff, t_rated_count, ct_rated_count, placement_ignored_count, Float:placement_t_avg, Float:placement_ct_avg)
{
    new old_elo = g_elo[id];
    new old_elo_cents = g_elo_cents[id];
    new team = g_round_team[id];
    new bool:won = team == g_round_winner;
    new bool:placement = is_in_placement(id);
    new bool:save_test_placement = should_save_testmode_placement(placement, testmode);
    new bool:smaller_team = is_player_on_smaller_team(team, t_count, ct_count);
    new Float:uneven_multiplier = get_uneven_result_multiplier(team_diff, smaller_team, won);

    new Float:own_avg = team == TEAM_T ? t_avg : ct_avg;
    new Float:enemy_avg = team == TEAM_T ? ct_avg : t_avg;
    new own_rated_count = team == TEAM_T ? t_rated_count : ct_rated_count;
    new enemy_rated_count = team == TEAM_T ? ct_rated_count : t_rated_count;
    new Float:enemy_placement_avg = team == TEAM_T ? placement_ct_avg : placement_t_avg;
    new Float:rated_vs_placement_multiplier = 1.0;

    if (!placement && get_pcvar_num(g_cvar_ignore_placement_in_team_avg)
        && enemy_rated_count < get_pcvar_num(g_cvar_min_rated_enemies_for_full_elo))
    {
        rated_vs_placement_multiplier = get_pcvar_float(g_cvar_rated_vs_placement_multiplier);

        if (rated_vs_placement_multiplier < 0.0)
        {
            rated_vs_placement_multiplier = 0.0;
        }
    }

    new Float:expected = calculate_expected_score(own_avg, enemy_avg);
    new Float:result = won ? 1.0 : 0.0;
    new Float:k = get_k_coefficient(old_elo, g_ranked_rounds[id]);
    new Float:base_delta = k * (result - expected);
    new Float:perf_delta = get_performance_modifier(id, placement);
    new Float:placement_weight = 1.0;
    new Float:raw_delta = (base_delta + perf_delta) * map_multiplier * player_multiplier * uneven_multiplier * rated_vs_placement_multiplier;
    new delta_cents = floatround(raw_delta * float(ELO_SCALE));
    new before_softcap_cents = delta_cents;
    new Float:daily_multiplier = 1.0;
    new placement_target = 0;

    if (get_pcvar_num(g_cvar_placement_weight_multipliers))
    {
        placement_weight = map_multiplier * player_multiplier * uneven_multiplier;
    }

    if (placement_weight < 0.0)
    {
        placement_weight = 0.0;
    }

    if (!get_pcvar_num(g_cvar_fractional_enabled))
    {
        delta_cents = elo_to_cents(floatround(raw_delta));
    }

    delta_cents = cap_round_delta_cents(delta_cents);
    delta_cents = apply_win_loss_bounds_cents(won, delta_cents);
    delta_cents = apply_daily_softcap_cents(id, delta_cents, daily_multiplier);

    new delta_before_carry_cents = delta_cents;
    new bool:carry_applied = false;
    delta_cents = apply_carry_protection_cents(id, won, smaller_team, delta_cents, carry_applied);

    new new_elo_cents = old_elo_cents + delta_cents;

    if (placement)
    {
        placement_target = calculate_placement_target(enemy_avg, won, perf_delta);

        /*
         * Placement is a calibration period (chess / FACEIT style): every
         * round the player's ELO is set to the running weighted average of
         * their placement targets, so strong play climbs quickly and weak
         * play drops. The weighted average converges smoothly so there is no
         * snap-back. clamp_placement_elo() inside calculate_placement_estimate
         * keeps the result inside the placement band.
         */
        new_elo_cents = elo_to_cents(calculate_placement_estimate(id, placement_target, placement_weight, testmode && !save_test_placement));
    }
    else if (new_elo_cents < 0)
    {
        new_elo_cents = 0;
    }

    if (!placement)
    {
        if (!won && new_elo_cents > old_elo_cents)
        {
            new_elo_cents = old_elo_cents;
        }
        else if (won && get_pcvar_num(g_cvar_won_round_min_delta) >= 0 && new_elo_cents < old_elo_cents)
        {
            new_elo_cents = old_elo_cents;
        }
    }

    new applied_delta_cents = new_elo_cents - old_elo_cents;
    new applied_delta = cents_to_elo_trunc(applied_delta_cents);

    g_session_delta[id] += applied_delta;
    g_session_delta_cents[id] += applied_delta_cents;
    if (applied_delta_cents > 0)
    {
        g_session_gain[id] += applied_delta;
        g_session_gain_cents[id] += applied_delta_cents;

        if (!testmode && !placement)
        {
            update_daily_gain_cents(id, applied_delta_cents);
        }
    }

    g_session_rounds[id]++;

    if (won)
    {
        g_session_wins[id]++;
    }
    else
    {
        g_session_losses[id]++;
    }

    if (placement && !save_test_placement)
    {
        g_session_placement_target_sum[id] += float(placement_target) * placement_weight;
        g_session_placement_weight_sum[id] += placement_weight;
    }

    if (!testmode || save_test_placement)
    {
        if (placement)
        {
            g_placement_target_sum[id] += float(placement_target) * placement_weight;
            g_placement_weight_sum[id] += placement_weight;
        }

        set_elo_cents(id, new_elo_cents);

        if (!testmode)
        {
            g_ranked_rounds[id]++;

            if (won)
            {
                g_wins[id]++;
            }
            else
            {
                g_losses[id]++;
            }

            if (g_elo[id] > g_highest_elo[id])
            {
                g_highest_elo[id] = g_elo[id];
            }
        }
        else if (save_test_placement)
        {
            g_ranked_rounds[id]++;

            if (g_elo[id] > g_highest_elo[id])
            {
                g_highest_elo[id] = g_elo[id];
            }
        }

        save_player(id, false);
    }

    print_round_delta(id, old_elo_cents, new_elo_cents, applied_delta_cents, expected, k, perf_delta, placement, testmode);
    log_round_delta(id, old_elo_cents, new_elo_cents, applied_delta_cents, before_softcap_cents, delta_before_carry_cents, expected, k, base_delta, perf_delta, daily_multiplier, placement, placement_target, placement_weight, testmode, team_diff, uneven_multiplier, t_avg, ct_avg, smaller_team, carry_applied, own_rated_count, enemy_rated_count, placement_ignored_count, rated_vs_placement_multiplier, enemy_avg, enemy_placement_avg);
    update_scoreboard_tag(id);
}

stock print_round_delta(id, old_elo_cents, new_elo_cents, delta_cents, Float:expected, Float:k, Float:perf_delta, bool:placement, bool:testmode)
{
    if (!get_pcvar_num(g_cvar_show_round_delta))
    {
        return;
    }

    new delta_text[16], old_elo_text[16], new_elo_text[16];
    format_delta_cents(delta_cents, delta_text, charsmax(delta_text));
    format_elo_cents(old_elo_cents, old_elo_text, charsmax(old_elo_text));
    format_elo_cents(new_elo_cents, new_elo_text, charsmax(new_elo_text));

    if (placement)
    {
        if (g_ranked_rounds[id] >= get_placement_rounds())
        {
            client_print(id, print_chat, "[SAVEKAI ELO] Placement baigtas: %s | %s -> %s.",
                delta_text,
                old_elo_text,
                new_elo_text
            );
        }
        else
        {
            client_print(id, print_chat, "[SAVEKAI ELO] Placement: %s | %s -> %s | %d/%d roundu.",
                delta_text,
                old_elo_text,
                new_elo_text,
                g_ranked_rounds[id],
                get_placement_rounds()
            );
        }

        if (testmode)
        {
            client_print(id, print_chat, "[SAVEKAI ELO] Test mode: placement ELO nesaugomas kaip official ELO.");
        }

        if (get_pcvar_num(g_cvar_debug_chat))
        {
            client_print(id, print_chat, "[SAVEKAI ELO] Exp %.2f | K %.1f | Perf %.2f", expected, k, perf_delta);
        }

        return;
    }

    if (testmode)
    {
        client_print(id, print_chat, "[SAVEKAI ELO] Test mode: %s ELO | %s -> %s butu pritaikyta, bet nesaugoma.",
            delta_text,
            old_elo_text,
            new_elo_text
        );

        if (get_pcvar_num(g_cvar_debug_chat))
        {
            client_print(id, print_chat, "[SAVEKAI ELO] Old %s -> New %s | Exp %.2f | K %.1f | Perf %.2f", old_elo_text, new_elo_text, expected, k, perf_delta);
        }

        return;
    }

    client_print(id, print_chat, "[SAVEKAI ELO] %s ELO | %s -> %s",
        delta_text,
        old_elo_text,
        new_elo_text
    );

    if (get_pcvar_num(g_cvar_debug_chat))
    {
        client_print(id, print_chat, "[SAVEKAI ELO] Old %s -> New %s | Exp %.2f | K %.1f | Perf %.2f", old_elo_text, new_elo_text, expected, k, perf_delta);
    }
}

stock log_round_delta(id, old_elo_cents, new_elo_cents, delta_cents, before_softcap_cents, delta_before_carry_cents, Float:expected, Float:k, Float:base_delta, Float:perf_delta, Float:daily_multiplier, bool:placement, placement_target, Float:placement_weight, bool:testmode, team_diff, Float:uneven_multiplier, Float:effective_t_avg, Float:effective_ct_avg, bool:smaller_team, bool:carry_applied, own_rated_count, enemy_rated_count, placement_ignored_count, Float:rated_vs_placement_multiplier, Float:rated_avg_used, Float:placement_avg_used)
{
    if (!get_pcvar_num(g_cvar_log_enabled))
    {
        return;
    }

    new name[NAME_LEN], delta_text[16], old_elo_text[16], new_elo_text[16];
    new before_softcap_text[16], delta_before_carry_text[16], old_rank[48], new_rank[48];
    new team_text[4];
    get_user_name(id, name, charsmax(name));
    sanitize_name(name, charsmax(name));
    format_delta_cents(delta_cents, delta_text, charsmax(delta_text));
    format_elo_cents(old_elo_cents, old_elo_text, charsmax(old_elo_text));
    format_elo_cents(new_elo_cents, new_elo_text, charsmax(new_elo_text));
    format_delta_cents(before_softcap_cents, before_softcap_text, charsmax(before_softcap_text));
    format_delta_cents(delta_before_carry_cents, delta_before_carry_text, charsmax(delta_before_carry_text));
    get_rank_title_by_elo(cents_to_elo_floor(old_elo_cents), old_rank, charsmax(old_rank));
    get_rank_title_by_elo(cents_to_elo_floor(new_elo_cents), new_rank, charsmax(new_rank));

    if (g_round_team[id] == TEAM_T)
    {
        copy(team_text, charsmax(team_text), "T");
    }
    else
    {
        copy(team_text, charsmax(team_text), "CT");
    }

    log_to_file("savekai_elo.log",
        "%s auth=%s team=%s old=%s new=%s delta=%s old_delta=%s new_delta=%s before_softcap=%s expected=%.2f k=%.1f base=%.2f perf=%.2f daily_mult=%.2f placement=%d target=%d weight=%.2f testmode=%d",
        name,
        g_authid[id],
        team_text,
        old_elo_text,
        new_elo_text,
        delta_text,
        delta_before_carry_text,
        delta_text,
        before_softcap_text,
        expected,
        k,
        base_delta,
        perf_delta,
        daily_multiplier,
        placement ? 1 : 0,
        placement_target,
        placement_weight,
        testmode ? 1 : 0
    );

    log_to_file("savekai_elo.log",
        "DETAIL auth=%s team_size_diff=%d uneven_mult=%.2f effective_T_avg=%.1f effective_CT_avg=%.1f player_is_smaller_team=%d carry_protection_applied=%d kills=%d deaths=%d damage=%d mvp=%d plant=%d defuse=%d tk=%d suicide=%d clutch=%d old_rank=%s new_rank=%s own_rated_count=%d enemy_rated_count=%d placement_players_ignored=%d rated_vs_placement_multiplier=%.2f rated_avg_used=%.1f placement_avg_used=%.1f",
        g_authid[id],
        team_diff,
        uneven_multiplier,
        effective_t_avg,
        effective_ct_avg,
        smaller_team ? 1 : 0,
        carry_applied ? 1 : 0,
        g_round_kills[id],
        g_round_deaths[id],
        g_round_damage[id],
        g_round_mvp[id] ? 1 : 0,
        g_round_plants[id],
        g_round_defuses[id],
        g_round_teamkills[id],
        g_round_suicides[id],
        g_round_clutch[id],
        old_rank,
        new_rank,
        own_rated_count,
        enemy_rated_count,
        placement_ignored_count,
        rated_vs_placement_multiplier,
        rated_avg_used,
        placement_avg_used
    );
}

stock bool:is_round_player_valid(id)
{
    if (id < 1 || id > MAX_CLIENTS || !g_round_eligible[id])
    {
        return false;
    }

    if (!is_user_connected(id) || is_user_bot(id) || is_user_hltv(id) || !g_loaded[id])
    {
        return false;
    }

    new team = get_user_team(id);

    if (team != TEAM_T && team != TEAM_CT)
    {
        return false;
    }

    return team == g_round_team[id];
}

stock log_round_snapshot()
{
    if (!get_pcvar_num(g_cvar_log_enabled))
    {
        return;
    }

    new map_name[32];
    new eligible_count, t_count, ct_count;
    get_mapname(map_name, charsmax(map_name));

    for (new id = 1; id <= MAX_CLIENTS; id++)
    {
        if (!g_round_eligible[id])
        {
            continue;
        }

        eligible_count++;

        if (g_round_team[id] == TEAM_T)
        {
            t_count++;
        }
        else if (g_round_team[id] == TEAM_CT)
        {
            ct_count++;
        }
    }

    log_to_file("savekai_elo.log",
        "Round snapshot map=%s mode=%d eligible=%d T=%d CT=%d",
        map_name,
        get_savekai_current_mode(),
        eligible_count,
        t_count,
        ct_count
    );
}

stock log_round_player_skip_if_needed(id)
{
    if (!get_pcvar_num(g_cvar_log_enabled) || id < 1 || id > MAX_CLIENTS || !g_round_eligible[id])
    {
        return;
    }

    new reason[64];
    get_round_player_skip_reason(id, reason, charsmax(reason));

    log_round_player_skip_direct(id, reason);
}

stock log_round_player_skip_direct(id, const reason[])
{
    if (!get_pcvar_num(g_cvar_log_enabled) || id < 1 || id > MAX_CLIENTS || !g_round_eligible[id])
    {
        return;
    }

    new name[NAME_LEN];

    if (is_user_connected(id))
    {
        get_user_name(id, name, charsmax(name));
        sanitize_name(name, charsmax(name));
    }
    else
    {
        copy(name, charsmax(name), "disconnected");
    }

    log_to_file("savekai_elo.log",
        "Player skipped name=%s auth=%s start_team=%d current_team=%d reason=%s",
        name,
        g_authid[id],
        g_round_team[id],
        is_user_connected(id) ? get_user_team(id) : TEAM_NONE,
        reason
    );
}

stock get_round_player_skip_reason(id, output[], output_len)
{
    if (id < 1 || id > MAX_CLIENTS)
    {
        copy(output, output_len, "invalid id");
        return;
    }

    if (!g_round_eligible[id])
    {
        copy(output, output_len, "not eligible at round start");
        return;
    }

    if (!is_user_connected(id))
    {
        copy(output, output_len, "disconnected before round end");
        return;
    }

    if (is_user_bot(id))
    {
        copy(output, output_len, "bot");
        return;
    }

    if (is_user_hltv(id))
    {
        copy(output, output_len, "hltv");
        return;
    }

    if (!g_loaded[id])
    {
        copy(output, output_len, "elo not loaded");
        return;
    }

    new team = get_user_team(id);

    if (team != TEAM_T && team != TEAM_CT)
    {
        copy(output, output_len, "spectator or invalid team");
        return;
    }

    if (team != g_round_team[id])
    {
        copy(output, output_len, "changed team mid-round");
        return;
    }

    copy(output, output_len, "unknown");
}

stock Float:calculate_expected_score(Float:own_avg, Float:enemy_avg)
{
    new Float:exponent = (enemy_avg - own_avg) / 400.0;
    return 1.0 / (1.0 + floatpower(10.0, exponent));
}

stock Float:get_k_coefficient(elo, ranked_rounds)
{
    if (is_placement_round_count(ranked_rounds))
    {
        return get_pcvar_float(g_cvar_k_placement);
    }

    if (ranked_rounds < get_provisional_rounds())
    {
        return get_pcvar_float(g_cvar_k_provisional);
    }

    if (elo >= 2600)
    {
        return get_pcvar_float(g_cvar_k_2600);
    }

    if (elo >= 2400)
    {
        return get_pcvar_float(g_cvar_k_2400);
    }

    if (elo >= 2200)
    {
        return get_pcvar_float(g_cvar_k_2200);
    }

    return get_pcvar_float(g_cvar_k_normal);
}

stock Float:get_performance_modifier(id, bool:placement)
{
    if (!get_pcvar_num(g_cvar_perf_enabled))
    {
        return 0.0;
    }

    if (placement && !get_pcvar_num(g_cvar_placement_use_performance))
    {
        return 0.0;
    }

    new Float:modifier = 0.0;
    modifier += float(g_round_kills[id]) * get_pcvar_float(g_cvar_perf_kill);
    modifier += float(g_round_deaths[id]) * get_pcvar_float(g_cvar_perf_death);

    new Float:damage_divisor = get_pcvar_float(g_cvar_perf_damage_divisor);

    if (damage_divisor < 1.0)
    {
        damage_divisor = 400.0;
    }

    modifier += float(g_round_damage[id]) / damage_divisor;

    if (g_round_mvp[id])
    {
        modifier += get_pcvar_float(g_cvar_perf_mvp);
    }

    modifier += float(g_round_plants[id]) * get_pcvar_float(g_cvar_perf_plant);
    modifier += float(g_round_defuses[id]) * get_pcvar_float(g_cvar_perf_defuse);
    modifier += float(g_round_teamkills[id]) * get_pcvar_float(g_cvar_perf_teamkill);
    modifier += float(g_round_suicides[id]) * get_pcvar_float(g_cvar_perf_suicide);

    switch (g_round_clutch[id])
    {
        case 2:
        {
            modifier += get_pcvar_float(g_cvar_perf_clutch_1v2);
        }
        case 3:
        {
            modifier += get_pcvar_float(g_cvar_perf_clutch_1v3);
        }
        case 4:
        {
            modifier += get_pcvar_float(g_cvar_perf_clutch_1v4);
        }
    }

    new Float:max_bonus = get_pcvar_float(g_cvar_perf_max_bonus);
    new Float:max_penalty = get_pcvar_float(g_cvar_perf_max_penalty);

    if (max_bonus < 0.0)
    {
        max_bonus = 0.0;
    }

    if (max_penalty > 0.0)
    {
        max_penalty = -max_penalty;
    }

    if (modifier > max_bonus)
    {
        modifier = max_bonus;
    }

    if (modifier < max_penalty)
    {
        modifier = max_penalty;
    }

    return modifier;
}

stock apply_win_loss_bounds(bool:won, delta)
{
    if (won)
    {
        new min_win = get_pcvar_num(g_cvar_won_round_min_delta);

        if (delta < min_win)
        {
            return min_win;
        }
    }
    else
    {
        new max_loss = get_pcvar_num(g_cvar_lost_round_max_delta);

        if (delta > max_loss)
        {
            return max_loss;
        }
    }

    return delta;
}

stock apply_win_loss_bounds_cents(bool:won, delta_cents)
{
    if (won)
    {
        new min_win_cents = floatround(get_pcvar_float(g_cvar_won_round_min_delta) * float(ELO_SCALE));

        if (delta_cents < min_win_cents)
        {
            return min_win_cents;
        }
    }
    else
    {
        new max_loss_cents = floatround(get_pcvar_float(g_cvar_lost_round_max_delta) * float(ELO_SCALE));

        if (delta_cents > max_loss_cents)
        {
            return max_loss_cents;
        }
    }

    return delta_cents;
}

stock apply_carry_protection(id, bool:won, bool:smaller_team, delta, &bool:carry_applied)
{
    carry_applied = false;

    if (won || !get_pcvar_num(g_cvar_perf_carry_protection))
    {
        return delta;
    }

    if (delta > 0)
    {
        delta = 0;
    }

    new carry_kills = get_pcvar_num(g_cvar_perf_carry_kills);
    new carry_damage = get_pcvar_num(g_cvar_perf_carry_damage);
    new hardcarry_kills = get_pcvar_num(g_cvar_perf_hardcarry_kills);
    new hardcarry_damage = get_pcvar_num(g_cvar_perf_hardcarry_damage);
    new carry_loss_cap = normalize_loss_cap(get_pcvar_num(g_cvar_perf_carry_loss_cap));
    new hardcarry_loss_cap = normalize_loss_cap(get_pcvar_num(g_cvar_perf_hardcarry_loss_cap));

    if (carry_kills < 1)
    {
        carry_kills = 1;
    }

    if (hardcarry_kills < 1)
    {
        hardcarry_kills = carry_kills;
    }

    if (carry_damage < 0)
    {
        carry_damage = 0;
    }

    if (hardcarry_damage < 0)
    {
        hardcarry_damage = carry_damage;
    }

    if (smaller_team && g_round_kills[id] >= carry_kills)
    {
        carry_applied = true;
        return max_int(delta, hardcarry_loss_cap);
    }

    if (g_round_kills[id] >= hardcarry_kills && g_round_damage[id] >= hardcarry_damage)
    {
        carry_applied = true;
        return max_int(delta, hardcarry_loss_cap);
    }

    if (g_round_kills[id] >= carry_kills)
    {
        carry_applied = true;
        return max_int(delta, carry_loss_cap);
    }

    return delta;
}

stock apply_carry_protection_cents(id, bool:won, bool:smaller_team, delta_cents, &bool:carry_applied)
{
    carry_applied = false;

    if (won || !get_pcvar_num(g_cvar_perf_carry_protection))
    {
        return delta_cents;
    }

    if (delta_cents > 0)
    {
        delta_cents = 0;
    }

    new carry_kills = get_pcvar_num(g_cvar_perf_carry_kills);
    new carry_damage = get_pcvar_num(g_cvar_perf_carry_damage);
    new hardcarry_kills = get_pcvar_num(g_cvar_perf_hardcarry_kills);
    new hardcarry_damage = get_pcvar_num(g_cvar_perf_hardcarry_damage);
    new carry_loss_cap_cents = normalize_loss_cap_cents(get_pcvar_float(g_cvar_perf_carry_loss_cap));
    new hardcarry_loss_cap_cents = normalize_loss_cap_cents(get_pcvar_float(g_cvar_perf_hardcarry_loss_cap));

    if (carry_kills < 1)
    {
        carry_kills = 1;
    }

    if (hardcarry_kills < 1)
    {
        hardcarry_kills = carry_kills;
    }

    if (carry_damage < 0)
    {
        carry_damage = 0;
    }

    if (hardcarry_damage < 0)
    {
        hardcarry_damage = carry_damage;
    }

    if (smaller_team && g_round_kills[id] >= carry_kills)
    {
        carry_applied = true;
        return max_int(delta_cents, hardcarry_loss_cap_cents);
    }

    if (g_round_kills[id] >= hardcarry_kills && g_round_damage[id] >= hardcarry_damage)
    {
        carry_applied = true;
        return max_int(delta_cents, hardcarry_loss_cap_cents);
    }

    if (g_round_kills[id] >= carry_kills)
    {
        carry_applied = true;
        return max_int(delta_cents, carry_loss_cap_cents);
    }

    return delta_cents;
}

stock normalize_loss_cap(cap)
{
    if (cap > 0)
    {
        cap = 0;
    }

    return cap;
}

stock normalize_loss_cap_cents(Float:cap)
{
    if (cap > 0.0)
    {
        cap = 0.0;
    }

    return floatround(cap * float(ELO_SCALE));
}

stock max_int(a, b)
{
    return a > b ? a : b;
}

stock calculate_placement_target(Float:enemy_avg, bool:won, Float:perf_delta)
{
    new Float:target = enemy_avg;

    if (won)
    {
        target += get_pcvar_float(g_cvar_placement_win_shift);
    }
    else
    {
        target -= get_pcvar_float(g_cvar_placement_loss_shift);
    }

    target += perf_delta * get_pcvar_float(g_cvar_placement_perf_scale);

    new Float:max_above = get_pcvar_float(g_cvar_placement_max_above_enemy);
    new Float:max_below = get_pcvar_float(g_cvar_placement_max_below_enemy);

    if (max_above > 0.0 && target > enemy_avg + max_above)
    {
        target = enemy_avg + max_above;
    }

    if (max_below > 0.0 && target < enemy_avg - max_below)
    {
        target = enemy_avg - max_below;
    }

    return clamp_placement_elo(floatround(target));
}

stock calculate_placement_estimate(id, placement_target, Float:placement_weight, bool:testmode)
{
    new Float:target_sum = g_placement_target_sum[id] + (float(placement_target) * placement_weight);
    new Float:weight_sum = g_placement_weight_sum[id] + placement_weight;

    if (testmode)
    {
        target_sum += g_session_placement_target_sum[id];
        weight_sum += g_session_placement_weight_sum[id];
    }

    if (weight_sum <= 0.0)
    {
        return clamp_placement_elo(placement_target);
    }

    return clamp_placement_elo(floatround(target_sum / weight_sum));
}

stock apply_daily_softcap(id, delta, &Float:effective_multiplier)
{
    effective_multiplier = 1.0;

    if (delta <= 0 || !get_pcvar_num(g_cvar_daily_softcap_enabled))
    {
        return delta;
    }

    refresh_daily_window(id);

    new original_delta = delta;
    new remaining = delta;
    new current_gain = get_effective_daily_gain(id);
    new Float:adjusted = 0.0;

    adjusted += consume_daily_tier(remaining, current_gain, get_pcvar_num(g_cvar_daily_softcap_1), get_pcvar_float(g_cvar_daily_mult_1));
    adjusted += consume_daily_tier(remaining, current_gain, get_pcvar_num(g_cvar_daily_softcap_2), get_pcvar_float(g_cvar_daily_mult_2));
    adjusted += consume_daily_tier(remaining, current_gain, get_pcvar_num(g_cvar_daily_softcap_3), get_pcvar_float(g_cvar_daily_mult_3));

    if (remaining > 0)
    {
        adjusted += float(remaining) * get_pcvar_float(g_cvar_daily_mult_4);
    }

    new adjusted_delta = floatround(adjusted);

    if (original_delta > 0)
    {
        effective_multiplier = float(adjusted_delta) / float(original_delta);
    }

    return adjusted_delta;
}

stock apply_daily_softcap_cents(id, delta_cents, &Float:effective_multiplier)
{
    effective_multiplier = 1.0;

    if (delta_cents <= 0 || !get_pcvar_num(g_cvar_daily_softcap_enabled))
    {
        return delta_cents;
    }

    refresh_daily_window(id);

    new original_delta_cents = delta_cents;
    new remaining_cents = delta_cents;
    new current_gain_cents = g_daily_gain_cents[id];
    new Float:adjusted = 0.0;

    adjusted += consume_daily_tier_cents(remaining_cents, current_gain_cents, get_pcvar_num(g_cvar_daily_softcap_1), get_pcvar_float(g_cvar_daily_mult_1));
    adjusted += consume_daily_tier_cents(remaining_cents, current_gain_cents, get_pcvar_num(g_cvar_daily_softcap_2), get_pcvar_float(g_cvar_daily_mult_2));
    adjusted += consume_daily_tier_cents(remaining_cents, current_gain_cents, get_pcvar_num(g_cvar_daily_softcap_3), get_pcvar_float(g_cvar_daily_mult_3));

    if (remaining_cents > 0)
    {
        adjusted += float(remaining_cents) * get_pcvar_float(g_cvar_daily_mult_4);
    }

    new adjusted_delta_cents = floatround(adjusted);

    if (original_delta_cents > 0)
    {
        effective_multiplier = float(adjusted_delta_cents) / float(original_delta_cents);
    }

    return adjusted_delta_cents;
}

stock Float:consume_daily_tier(&remaining, &current_gain, tier_limit, Float:multiplier)
{
    if (remaining <= 0)
    {
        return 0.0;
    }

    if (tier_limit <= current_gain)
    {
        return 0.0;
    }

    new available = tier_limit - current_gain;

    if (available > remaining)
    {
        available = remaining;
    }

    remaining -= available;
    current_gain += available;
    return float(available) * multiplier;
}

stock Float:consume_daily_tier_cents(&remaining_cents, &current_gain_cents, tier_limit, Float:multiplier)
{
    if (remaining_cents <= 0)
    {
        return 0.0;
    }

    new tier_limit_cents = elo_to_cents(tier_limit);

    if (tier_limit_cents <= current_gain_cents)
    {
        return 0.0;
    }

    new available_cents = tier_limit_cents - current_gain_cents;

    if (available_cents > remaining_cents)
    {
        available_cents = remaining_cents;
    }

    remaining_cents -= available_cents;
    current_gain_cents += available_cents;
    return float(available_cents) * multiplier;
}

stock update_daily_gain(id, delta)
{
    if (delta <= 0)
    {
        return;
    }

    refresh_daily_window(id);
    g_daily_gain[id] += delta;
}

stock update_daily_gain_cents(id, delta_cents)
{
    if (delta_cents <= 0)
    {
        return;
    }

    refresh_daily_window(id);
    g_daily_gain_cents[id] += delta_cents;
    g_daily_gain[id] = cents_to_elo_floor(g_daily_gain_cents[id]);
}

stock get_effective_daily_gain(id)
{
    refresh_daily_window(id);

    return g_daily_gain[id];
}

stock refresh_daily_window(id)
{
    new today = get_current_day();

    if (g_daily_day[id] != today)
    {
        g_daily_day[id] = today;
        g_daily_gain[id] = 0;
        g_daily_gain_cents[id] = 0;
    }
}

stock get_current_day()
{
    return get_systime() / 86400;
}

stock bool:is_in_placement(id)
{
    if (!get_pcvar_num(g_cvar_placement_enabled))
    {
        return false;
    }

    return is_placement_round_count(g_ranked_rounds[id]);
}

stock bool:should_save_testmode_placement(bool:placement, bool:testmode)
{
    return testmode && placement && get_pcvar_num(g_cvar_testmode_save_placement) != 0;
}

stock bool:can_save_testmode_placement_state(id)
{
    if (!get_pcvar_num(g_cvar_testmode_save_placement))
    {
        return false;
    }

    return g_ranked_rounds[id] <= get_placement_rounds();
}

stock bool:is_placement_round_count(ranked_rounds)
{
    if (!get_pcvar_num(g_cvar_placement_enabled))
    {
        return false;
    }

    return ranked_rounds < get_placement_rounds();
}

stock get_placement_rounds()
{
    new placement_rounds = get_pcvar_num(g_cvar_placement_rounds);
    new min_rounds = get_placement_min_rounds();

    if (placement_rounds < min_rounds)
    {
        placement_rounds = min_rounds;
    }

    if (placement_rounds < 1)
    {
        placement_rounds = 40;
    }

    return placement_rounds;
}

stock get_placement_min_rounds()
{
    new min_rounds = get_pcvar_num(g_cvar_placement_min_rounds);

    if (min_rounds < 1)
    {
        min_rounds = 20;
    }

    return min_rounds;
}

stock get_provisional_rounds()
{
    new provisional_rounds = get_pcvar_num(g_cvar_provisional_rounds);
    new placement_rounds = get_placement_rounds();

    if (provisional_rounds < placement_rounds)
    {
        provisional_rounds = placement_rounds;
    }

    return provisional_rounds;
}

stock clamp_placement_elo(elo)
{
    new min_elo = get_pcvar_num(g_cvar_placement_min_elo);
    new max_elo = get_pcvar_num(g_cvar_placement_max_elo);

    if (min_elo < 0)
    {
        min_elo = 800;
    }

    if (max_elo < min_elo)
    {
        max_elo = 2000;
    }

    if (max_elo > 2000)
    {
        max_elo = 2000;
    }

    if (elo < min_elo)
    {
        return min_elo;
    }

    if (elo > max_elo)
    {
        return max_elo;
    }

    return elo;
}

stock mark_round_mvp()
{
    new best_id = 0;
    new Float:best_score = 0.0;

    for (new id = 1; id <= MAX_CLIENTS; id++)
    {
        g_round_mvp[id] = false;

        if (!is_round_player_valid(id) || g_round_team[id] != g_round_winner)
        {
            continue;
        }

        new Float:score = float(g_round_kills[id] * 2) + (float(g_round_damage[id]) / 150.0);
        score += float(g_round_plants[id] * 2);
        score += float(g_round_defuses[id] * 3);
        score += float(g_round_clutch[id]);
        score -= float(g_round_deaths[id]) * 0.25;

        if (score > best_score)
        {
            best_score = score;
            best_id = id;
        }
    }

    if (best_id)
    {
        g_round_mvp[best_id] = true;
    }
}

stock update_clutch_state(attacker, attacker_team, victim_team)
{
    new teammates_alive = count_alive_team(attacker_team);
    new enemies_alive_before = count_alive_team(victim_team) + 1;

    if (teammates_alive != 1 || enemies_alive_before < 2)
    {
        return;
    }

    if (enemies_alive_before > 4)
    {
        enemies_alive_before = 4;
    }

    if (enemies_alive_before > g_round_clutch[attacker])
    {
        g_round_clutch[attacker] = enemies_alive_before;
    }
}

stock count_alive_team(team)
{
    new players[32], count, alive_count;
    get_players(players, count, "ach");

    for (new i = 0; i < count; i++)
    {
        if (get_user_team(players[i]) == team)
        {
            alive_count++;
        }
    }

    return alive_count;
}

stock get_logevent_player()
{
    new log_user[80], name[NAME_LEN];
    read_logargv(0, log_user, charsmax(log_user));
    parse_loguser(log_user, name, charsmax(name));

    if (name[0] == 0)
    {
        return 0;
    }

    return get_user_index(name);
}

stock Float:get_map_multiplier()
{
    new map_name[32];
    get_mapname(map_name, charsmax(map_name));

    if (equali(map_name, "aim_", 4) || equali(map_name, "awp_", 4) || equali(map_name, "fy_", 3))
    {
        return get_pcvar_float(g_cvar_arcade_multiplier);
    }

    return get_pcvar_float(g_cvar_normal_multiplier);
}

stock Float:get_player_count_multiplier(total_count)
{
    new full_players = get_pcvar_num(g_cvar_full_players);

    if (full_players < get_min_players())
    {
        full_players = get_min_players();
    }

    if (total_count < full_players)
    {
        return get_pcvar_float(g_cvar_lowplayer_multiplier);
    }

    return get_pcvar_float(g_cvar_normal_multiplier);
}

stock cap_round_delta(delta)
{
    new max_gain = get_pcvar_num(g_cvar_max_gain_round);
    new max_loss = get_pcvar_num(g_cvar_max_loss_round);

    if (max_gain < 1)
    {
        max_gain = 1;
    }

    if (max_loss < 1)
    {
        max_loss = 1;
    }

    if (delta > max_gain)
    {
        return max_gain;
    }

    if (delta < -max_loss)
    {
        return -max_loss;
    }

    return delta;
}

stock cap_round_delta_cents(delta_cents)
{
    new max_gain_cents = floatround(get_pcvar_float(g_cvar_max_gain_round) * float(ELO_SCALE));
    new max_loss_cents = floatround(get_pcvar_float(g_cvar_max_loss_round) * float(ELO_SCALE));

    if (max_gain_cents < ELO_SCALE)
    {
        max_gain_cents = ELO_SCALE;
    }

    if (max_loss_cents < ELO_SCALE)
    {
        max_loss_cents = ELO_SCALE;
    }

    if (delta_cents > max_gain_cents)
    {
        return max_gain_cents;
    }

    if (delta_cents < -max_loss_cents)
    {
        return -max_loss_cents;
    }

    return delta_cents;
}

stock get_min_players()
{
    new min_players = get_pcvar_num(g_cvar_min_players);

    if (min_players < 2)
    {
        min_players = 2;
    }

    return min_players;
}

stock get_min_team_players()
{
    new min_team_players = get_pcvar_num(g_cvar_min_team_players);

    if (min_team_players < 1)
    {
        min_team_players = 1;
    }

    return min_team_players;
}

stock get_max_team_diff()
{
    return get_pcvar_num(g_cvar_max_team_diff);
}

stock get_max_counted_team_diff()
{
    new max_counted_team_diff = get_pcvar_num(g_cvar_max_counted_team_diff);
    new legacy_max_team_diff = get_max_team_diff();

    if (legacy_max_team_diff >= 0 && legacy_max_team_diff < max_counted_team_diff)
    {
        max_counted_team_diff = legacy_max_team_diff;
    }

    return max_counted_team_diff;
}

stock Float:get_uneven_team_multiplier(team_diff)
{
    if (team_diff <= 0)
    {
        return 1.0;
    }

    new Float:multiplier = get_pcvar_float(g_cvar_uneven_team_multiplier);

    if (multiplier < 0.0)
    {
        multiplier = 0.0;
    }

    if (multiplier > 1.0)
    {
        multiplier = 1.0;
    }

    return multiplier;
}

stock Float:get_uneven_result_multiplier(team_diff, bool:smaller_team, bool:won)
{
    if (team_diff <= 0)
    {
        return 1.0;
    }

    if (won)
    {
        if (smaller_team)
        {
            return clamp_multiplier(get_pcvar_float(g_cvar_uneven_underdog_win_multiplier));
        }

        return clamp_multiplier(get_pcvar_float(g_cvar_uneven_favorite_win_multiplier));
    }

    if (smaller_team)
    {
        return clamp_multiplier(get_pcvar_float(g_cvar_uneven_underdog_loss_multiplier));
    }

    return clamp_multiplier(get_pcvar_float(g_cvar_uneven_favorite_loss_multiplier));
}

stock Float:clamp_multiplier(Float:multiplier)
{
    if (multiplier < 0.0)
    {
        multiplier = 0.0;
    }

    if (multiplier > 1.0)
    {
        multiplier = 1.0;
    }

    return multiplier;
}

stock Float:apply_team_size_bonus(t_count, ct_count, &Float:effective_t_avg, &Float:effective_ct_avg)
{
    if (t_count == ct_count)
    {
        return 0.0;
    }

    new Float:bonus = get_pcvar_float(g_cvar_team_size_elo_bonus);

    if (bonus < 0.0)
    {
        bonus = 0.0;
    }

    if (t_count > ct_count)
    {
        effective_t_avg += bonus;
        return bonus;
    }

    effective_ct_avg += bonus;
    return bonus;
}

stock bool:is_player_on_smaller_team(team, t_count, ct_count)
{
    if (t_count == ct_count)
    {
        return false;
    }

    if (team == TEAM_T)
    {
        return t_count < ct_count;
    }

    if (team == TEAM_CT)
    {
        return ct_count < t_count;
    }

    return false;
}

stock get_savekai_current_mode()
{
    if (!g_cvar_current_mode)
    {
        g_cvar_current_mode = get_cvar_pointer("savekai_current_mode");
    }

    if (g_cvar_current_mode)
    {
        return get_pcvar_num(g_cvar_current_mode);
    }

    if (get_pcvar_num(g_cvar_disable_non_normal_mode))
    {
        if (!g_warned_missing_mode_cvar)
        {
            log_amx("[SAVEKAI ELO] savekai_current_mode cvar missing; ELO rounds skipped safely.");
            log_to_file("savekai_elo.log", "WARNING savekai_current_mode missing; ELO rounds skipped safely.");
            g_warned_missing_mode_cvar = true;
        }

        return -1;
    }

    return 0;
}

stock bool:ensure_loaded(id)
{
    if (g_loaded[id])
    {
        return true;
    }

    if (is_user_connected(id))
    {
        load_player(id);
    }

    return g_loaded[id];
}

stock load_player(id)
{
    if (!is_user_connected(id) || is_user_bot(id) || is_user_hltv(id))
    {
        return;
    }

    if (!get_authid_key(id, g_authid[id], AUTH_LEN - 1))
    {
        return;
    }

    new start_elo = get_start_elo();
    set_elo_cents(id, elo_to_cents(start_elo));
    g_ranked_rounds[id] = 0;
    g_wins[id] = 0;
    g_losses[id] = 0;
    g_highest_elo[id] = start_elo;
    g_last_seen[id] = get_systime();
    g_daily_day[id] = get_current_day();
    g_daily_gain[id] = 0;
    g_daily_gain_cents[id] = 0;
    g_placement_target_sum[id] = 0.0;
    g_placement_weight_sum[id] = 0.0;

    new name[NAME_LEN];
    get_clean_user_name(id, name, charsmax(name));
    copy(g_clean_name[id], NAME_LEN - 1, name);
    sanitize_name(name, charsmax(name));
    copy(g_saved_name[id], NAME_LEN - 1, name);

    if (g_vault != INVALID_VAULT)
    {
        new loaded_name[NAME_LEN], elo, elo_cents, rounds, wins, losses, highest, last_seen, daily_day, daily_gain, daily_gain_cents;
        new Float:placement_sum, Float:placement_weight;

        if (load_elo_by_authid(g_authid[id], elo, elo_cents, rounds, wins, losses, highest, loaded_name, charsmax(loaded_name), last_seen, daily_day, daily_gain, daily_gain_cents, placement_sum, placement_weight))
        {
            set_elo_cents(id, elo_cents);
            g_ranked_rounds[id] = rounds;
            g_wins[id] = wins;
            g_losses[id] = losses;
            g_highest_elo[id] = highest > 0 ? highest : elo;
            g_last_seen[id] = last_seen;
            g_daily_day[id] = daily_day;
            g_daily_gain[id] = daily_gain;
            g_daily_gain_cents[id] = daily_gain_cents;
            g_placement_target_sum[id] = placement_sum;
            g_placement_weight_sum[id] = placement_weight;

            if (g_placement_weight_sum[id] <= 0.0 && g_ranked_rounds[id] > 0 && is_placement_round_count(g_ranked_rounds[id]))
            {
                g_placement_weight_sum[id] = float(g_ranked_rounds[id]);

                if (g_placement_target_sum[id] <= 0.0)
                {
                    g_placement_target_sum[id] = float(g_elo[id]) * g_placement_weight_sum[id];
                }
            }

            refresh_daily_window(id);

            if (loaded_name[0] != 0)
            {
                copy(g_saved_name[id], NAME_LEN - 1, loaded_name);
            }
        }

        if (!get_pcvar_num(g_cvar_testmode))
        {
            add_authid_to_slots(g_authid[id]);
        }
    }

    g_loaded[id] = true;
    save_player(id, false);
    update_scoreboard_tag(id);
}

stock save_player(id, bool:force)
{
    if (g_vault == INVALID_VAULT || !g_loaded[id] || g_authid[id][0] == 0)
    {
        return;
    }

    new bool:testmode = get_pcvar_num(g_cvar_testmode) != 0;

    if (!force && testmode && !can_save_testmode_placement_state(id))
    {
        return;
    }

    if (!testmode)
    {
        add_authid_to_slots(g_authid[id]);
    }

    new name[NAME_LEN];
    get_clean_user_name(id, name, charsmax(name));
    sanitize_name(name, charsmax(name));

    if (name[0] != 0)
    {
        copy(g_saved_name[id], NAME_LEN - 1, name);
    }

    new key[64], data[DATA_LEN];
    formatex(key, charsmax(key), "elo:%s", g_authid[id]);
    refresh_daily_window(id);
    formatex(data, charsmax(data), "%d %d %d %d %d %d %d %d %.3f %.3f %d %d %s",
        g_elo[id],
        g_ranked_rounds[id],
        g_wins[id],
        g_losses[id],
        g_highest_elo[id],
        get_systime(),
        g_daily_day[id],
        g_daily_gain[id],
        g_placement_target_sum[id],
        g_placement_weight_sum[id],
        g_elo_cents[id],
        g_daily_gain_cents[id],
        g_saved_name[id]
    );

    nvault_set(g_vault, key, data);
}

stock save_all_connected(bool:force)
{
    for (new id = 1; id <= MAX_CLIENTS; id++)
    {
        if (is_user_connected(id) && g_loaded[id])
        {
            save_player(id, force);
        }
    }
}

stock bool:load_elo_by_authid(const authid[], &elo, &elo_cents, &rounds, &wins, &losses, &highest, name[], name_len, &last_seen, &daily_day, &daily_gain, &daily_gain_cents, &Float:placement_sum, &Float:placement_weight)
{
    if (g_vault == INVALID_VAULT || authid[0] == 0)
    {
        return false;
    }

    new key[64], data[DATA_LEN];
    formatex(key, charsmax(key), "elo:%s", authid);

    if (!nvault_get(g_vault, key, data, charsmax(data)))
    {
        return false;
    }

    new elo_text[16], rounds_text[16], wins_text[16], losses_text[16], highest_text[16], seen_text[16];
    new daily_day_text[16], daily_gain_text[16], placement_sum_text[16], placement_weight_text[16];
    new elo_cents_text[16], daily_gain_cents_text[16];

    parse(data,
        elo_text, charsmax(elo_text),
        rounds_text, charsmax(rounds_text),
        wins_text, charsmax(wins_text),
        losses_text, charsmax(losses_text),
        highest_text, charsmax(highest_text),
        seen_text, charsmax(seen_text),
        daily_day_text, charsmax(daily_day_text),
        daily_gain_text, charsmax(daily_gain_text),
        placement_sum_text, charsmax(placement_sum_text),
        placement_weight_text, charsmax(placement_weight_text),
        elo_cents_text, charsmax(elo_cents_text),
        daily_gain_cents_text, charsmax(daily_gain_cents_text),
        name, name_len
    );

    elo = str_to_num(elo_text);
    rounds = str_to_num(rounds_text);
    wins = str_to_num(wins_text);
    losses = str_to_num(losses_text);
    highest = str_to_num(highest_text);
    last_seen = str_to_num(seen_text);
    daily_day = str_to_num(daily_day_text);
    daily_gain = str_to_num(daily_gain_text);
    placement_sum = str_to_float(placement_sum_text);
    placement_weight = str_to_float(placement_weight_text);
    elo_cents = elo_to_cents(elo);
    daily_gain_cents = elo_to_cents(daily_gain);

    if (elo_cents_text[0] != 0 && is_numeric_text(elo_cents_text))
    {
        elo_cents = str_to_num(elo_cents_text);
    }

    if (daily_gain_cents_text[0] != 0 && is_numeric_text(daily_gain_cents_text))
    {
        daily_gain_cents = str_to_num(daily_gain_cents_text);
    }
    else if (daily_gain_cents_text[0] != 0 && !is_numeric_text(daily_gain_cents_text) && name[0] == 0)
    {
        copy(name, name_len, daily_gain_cents_text);
    }
    else if (elo_cents_text[0] != 0 && !is_numeric_text(elo_cents_text) && name[0] == 0)
    {
        copy(name, name_len, elo_cents_text);
    }

    if (name[0] == 0 && placement_weight_text[0] != 0 && !is_float_text(placement_weight_text))
    {
        copy(name, name_len, placement_weight_text);
        placement_weight = 0.0;
    }
    else if (name[0] == 0 && placement_sum_text[0] != 0 && !is_float_text(placement_sum_text))
    {
        copy(name, name_len, placement_sum_text);
        placement_sum = 0.0;
        placement_weight = 0.0;
    }
    else if (name[0] == 0 && daily_gain_text[0] != 0 && !is_numeric_text(daily_gain_text))
    {
        copy(name, name_len, daily_gain_text);
        daily_gain = 0;
        placement_sum = 0.0;
        placement_weight = 0.0;
    }
    else if (name[0] == 0 && daily_day_text[0] != 0 && !is_numeric_text(daily_day_text))
    {
        copy(name, name_len, daily_day_text);
        daily_day = 0;
        daily_gain = 0;
        placement_sum = 0.0;
        placement_weight = 0.0;
    }

    if (elo_cents < 0)
    {
        elo_cents = 0;
    }

    elo = cents_to_elo_floor(elo_cents);
    daily_gain = cents_to_elo_floor(daily_gain_cents);

    if (placement_weight <= 0.0 && placement_sum > 0.0 && rounds > 0 && is_placement_round_count(rounds))
    {
        placement_weight = float(rounds);
    }

    return true;
}

stock load_slot_cache()
{
    g_slot_count_cache = 0;

    if (g_vault == INVALID_VAULT)
    {
        return;
    }

    new text[16];

    if (!nvault_get(g_vault, "slot_count", text, charsmax(text)))
    {
        return;
    }

    new total = str_to_num(text);

    if (total > MAX_TRACKED_PLAYERS)
    {
        total = MAX_TRACKED_PLAYERS;
    }

    for (new slot = 1; slot <= total; slot++)
    {
        new key[32];
        formatex(key, charsmax(key), "slot:%d", slot);

        if (nvault_get(g_vault, key, g_slot_authid_cache[slot], AUTH_LEN - 1))
        {
            g_slot_count_cache = slot;
        }
    }
}

stock add_authid_to_slots(const authid[])
{
    if (g_vault == INVALID_VAULT || authid[0] == 0)
    {
        return;
    }

    if (find_authid_slot(authid) > 0)
    {
        return;
    }

    if (g_slot_count_cache >= MAX_TRACKED_PLAYERS)
    {
        log_amx("[SAVEKAI ELO] Max tracked players reached: %d", MAX_TRACKED_PLAYERS);
        return;
    }

    g_slot_count_cache++;

    new key[32], total_text[16];
    formatex(key, charsmax(key), "slot:%d", g_slot_count_cache);
    nvault_set(g_vault, key, authid);

    num_to_str(g_slot_count_cache, total_text, charsmax(total_text));
    nvault_set(g_vault, "slot_count", total_text);

    copy(g_slot_authid_cache[g_slot_count_cache], AUTH_LEN - 1, authid);
}

stock find_authid_slot(const authid[])
{
    for (new slot = 1; slot <= g_slot_count_cache; slot++)
    {
        if (equal(g_slot_authid_cache[slot], authid))
        {
            return slot;
        }
    }

    return 0;
}

stock print_elo_to_player(receiver, target)
{
    new title[48], elo_text[16], daily_gain_text[16];
    get_rank_title(g_elo[target], g_ranked_rounds[target], title, charsmax(title));
    format_elo_cents(g_elo_cents[target], elo_text, charsmax(elo_text));
    format_elo_cents(g_daily_gain_cents[target], daily_gain_text, charsmax(daily_gain_text));

    client_print(receiver, print_chat, "[SAVEKAI ELO] Tavo ELO: %s | Rank: %s | Roundai: %d",
        elo_text,
        title,
        g_ranked_rounds[target]
    );
    client_print(receiver, print_chat, "[SAVEKAI ELO] W/L: %d/%d | Highest: %d",
        g_wins[target],
        g_losses[target],
        g_highest_elo[target]
    );

    if (is_placement_round_count(g_ranked_rounds[target]))
    {
        client_print(receiver, print_chat, "[SAVEKAI ELO] Placement: %d/%d roundu | Estimate: %s | Min: %d.",
            g_ranked_rounds[target],
            get_placement_rounds(),
            elo_text,
            get_placement_min_rounds()
        );
    }

    refresh_daily_window(target);
    format_elo_cents(g_daily_gain_cents[target], daily_gain_text, charsmax(daily_gain_text));
    client_print(receiver, print_chat, "[SAVEKAI ELO] Daily gain: +%s | Leaderboard nuo %d roundu.",
        daily_gain_text,
        get_pcvar_num(g_cvar_min_leaderboard_rounds)
    );

    if (get_pcvar_num(g_cvar_testmode))
    {
        if (get_pcvar_num(g_cvar_testmode_save_placement))
        {
            client_print(receiver, print_chat, "[SAVEKAI ELO] Test mode ON: placement saugomas, official ELO ne.");
        }
        else
        {
            client_print(receiver, print_chat, "[SAVEKAI ELO] Test mode ON: round ELO nesaugomas.");
        }
    }
}

stock print_elo_to_console(admin, target)
{
    new name[NAME_LEN], title[48], elo_text[16];
    get_user_name(target, name, charsmax(name));
    get_rank_title(g_elo[target], g_ranked_rounds[target], title, charsmax(title));
    format_elo_cents(g_elo_cents[target], elo_text, charsmax(elo_text));

    console_print(admin, "[SAVEKAI ELO] %s | ELO %s | Rank %s | Rounds %d | W/L %d/%d | Highest %d",
        name,
        elo_text,
        title,
        g_ranked_rounds[target],
        g_wins[target],
        g_losses[target],
        g_highest_elo[target]
    );
}

stock show_topelo_motd(id)
{
    new motd[MOTD_LEN];
    new len = 0;
    new min_rounds = get_pcvar_num(g_cvar_min_leaderboard_rounds);
    new top_elo_cents[TOP_SIZE];
    new top_rounds[TOP_SIZE];
    new top_name[TOP_SIZE][NAME_LEN];

    len += formatex(motd[len], charsmax(motd) - len,
        "<html><body bgcolor=#101010 text=#eeeeee><h2>SAVEKAI Top ELO</h2><table width=100%% cellpadding=4><tr><th>#</th><th>Name</th><th>ELO</th><th>Rounds</th><th>Rank</th></tr>"
    );

    for (new slot = 1; slot <= g_slot_count_cache; slot++)
    {
        new authid[AUTH_LEN];
        copy(authid, charsmax(authid), g_slot_authid_cache[slot]);

        if (authid[0] == 0)
        {
            continue;
        }

        new name[NAME_LEN], elo, elo_cents, rounds, wins, losses, highest, last_seen, daily_day, daily_gain, daily_gain_cents;
        new Float:placement_sum, Float:placement_weight;

        if (!load_elo_by_authid(authid, elo, elo_cents, rounds, wins, losses, highest, name, charsmax(name), last_seen, daily_day, daily_gain, daily_gain_cents, placement_sum, placement_weight))
        {
            continue;
        }

        if (rounds < min_rounds)
        {
            continue;
        }

        insert_topelo_candidate(name, elo_cents, rounds, top_elo_cents, top_rounds, top_name);
    }

    new shown = 0;

    for (new i = 0; i < TOP_SIZE; i++)
    {
        if (top_elo_cents[i] <= 0)
        {
            continue;
        }

        new safe_name[NAME_LEN * 2], title[48], elo_text[16];
        html_escape(top_name[i], safe_name, charsmax(safe_name));
        get_rank_title_by_elo(cents_to_elo_floor(top_elo_cents[i]), title, charsmax(title));
        format_elo_cents(top_elo_cents[i], elo_text, charsmax(elo_text));

        len += formatex(motd[len], charsmax(motd) - len,
            "<tr><td>%d</td><td>%s</td><td>%s</td><td>%d</td><td>%s</td></tr>",
            i + 1,
            safe_name,
            elo_text,
            top_rounds[i],
            title
        );
        shown++;
    }

    if (!shown)
    {
        len += formatex(motd[len], charsmax(motd) - len,
            "<tr><td colspan=5>No Season 0 leaderboard players yet. Players need %d+ saved ranked rounds.</td></tr>",
            min_rounds
        );
    }

    formatex(motd[len], charsmax(motd) - len,
        "</table><p>Season 0 Beta leaderboard. /rank stays normal CS stats; use /elo for SAVEKAI ELO.</p></body></html>"
    );

    show_motd(id, motd, "SAVEKAI Top ELO");
}

stock insert_topelo_candidate(const name[], elo_cents, rounds, top_elo_cents[], top_rounds[], top_name[][NAME_LEN])
{
    for (new pos = 0; pos < TOP_SIZE; pos++)
    {
        if (elo_cents <= top_elo_cents[pos])
        {
            continue;
        }

        for (new move = TOP_SIZE - 1; move > pos; move--)
        {
            top_elo_cents[move] = top_elo_cents[move - 1];
            top_rounds[move] = top_rounds[move - 1];
            copy(top_name[move], NAME_LEN - 1, top_name[move - 1]);
        }

        top_elo_cents[pos] = elo_cents;
        top_rounds[pos] = rounds;
        copy(top_name[pos], NAME_LEN - 1, name);
        break;
    }
}

stock set_player_elo_admin(admin, target, new_elo, const action[])
{
    if (!ensure_loaded(target))
    {
        console_print(admin, "[SAVEKAI ELO] Target ELO not loaded.");
        return;
    }

    if (new_elo < 0)
    {
        new_elo = 0;
    }

    new old_elo = g_elo[target];
    set_elo_cents(target, elo_to_cents(new_elo));

    if (g_elo[target] > g_highest_elo[target])
    {
        g_highest_elo[target] = g_elo[target];
    }

    save_player(target, true);
    update_scoreboard_tag(target);
    announce_admin_change(admin, target, action, old_elo, new_elo);
}

stock announce_admin_change(admin, target, const action[], old_elo, new_elo)
{
    new target_name[NAME_LEN];
    get_user_name(target, target_name, charsmax(target_name));

    console_print(admin, "[SAVEKAI ELO] %s: %s %d -> %d", action, target_name, old_elo, new_elo);
    client_print(target, print_chat, "[SAVEKAI ELO] Admin pakeite tavo ELO: %d -> %d", old_elo, new_elo);
    log_admin_change(admin, target, action, old_elo, new_elo, new_elo - old_elo);
}

stock log_admin_change(admin, target, const action[], old_elo, new_elo, delta)
{
    if (!get_pcvar_num(g_cvar_log_enabled))
    {
        return;
    }

    new admin_name[NAME_LEN], target_name[NAME_LEN];

    if (admin > 0 && is_user_connected(admin))
    {
        get_user_name(admin, admin_name, charsmax(admin_name));
    }
    else
    {
        copy(admin_name, charsmax(admin_name), "SERVER");
    }

    if (target > 0 && is_user_connected(target))
    {
        get_user_name(target, target_name, charsmax(target_name));
    }
    else
    {
        copy(target_name, charsmax(target_name), "none");
    }

    sanitize_name(admin_name, charsmax(admin_name));
    sanitize_name(target_name, charsmax(target_name));

    log_to_file("savekai_elo.log",
        "ADMIN action=%s admin=%s target=%s old=%d new=%d delta=%d",
        action,
        admin_name,
        target_name,
        old_elo,
        new_elo,
        delta
    );
}

stock get_admin_target(admin, arg_index)
{
    new target_arg[32];
    read_argv(arg_index, target_arg, charsmax(target_arg));

    new target = cmd_target(admin, target_arg, CMDTARGET_ALLOW_SELF);

    if (!target)
    {
        console_print(admin, "[SAVEKAI ELO] Player not found.");
        return 0;
    }

    if (!ensure_loaded(target))
    {
        console_print(admin, "[SAVEKAI ELO] Target ELO not loaded.");
        return 0;
    }

    return target;
}

stock get_start_elo()
{
    new start_elo = get_pcvar_num(g_cvar_start);

    if (start_elo < 0)
    {
        start_elo = 1000;
    }

    return start_elo;
}

stock get_rank_title(elo, ranked_rounds, output[], output_len)
{
    if (is_placement_round_count(ranked_rounds))
    {
        copy(output, output_len, "Placement");
        return;
    }

    get_rank_title_by_elo(elo, output, output_len);
}

stock get_rank_title_by_elo(elo, output[], output_len)
{
    if (elo < 1000)
    {
        copy(output, output_len, "Naujas");
    }
    else if (elo < 1400)
    {
        copy(output, output_len, "Pradedantysis");
    }
    else if (elo < 1800)
    {
        copy(output, output_len, "Vidutinis");
    }
    else if (elo < 2200)
    {
        copy(output, output_len, "Geras");
    }
    else if (elo < 2400)
    {
        copy(output, output_len, "SAVEKAI Meistras (SM)");
    }
    else if (elo < 2600)
    {
        copy(output, output_len, "SAVEKAI Tarptautinis Meistras (SIM)");
    }
    else
    {
        copy(output, output_len, "SAVEKAI Didmeistris (SGM)");
    }
}

stock bool:get_authid_key(id, output[], output_len)
{
    get_user_authid(id, output, output_len);

    if (output[0] == 0 ||
        equal(output, "STEAM_ID_PENDING") ||
        equal(output, "STEAM_ID_LAN") ||
        equal(output, "VALVE_ID_LAN") ||
        equal(output, "BOT") ||
        equal(output, "HLTV"))
    {
        output[0] = 0;
        return false;
    }

    return true;
}

stock bool:is_numeric_text(const text[])
{
    if (text[0] == 0)
    {
        return false;
    }

    new start = 0;

    if (text[0] == '-')
    {
        start = 1;
    }

    for (new i = start; text[i] != 0; i++)
    {
        if (text[i] < '0' || text[i] > '9')
        {
            return false;
        }
    }

    return text[start] != 0;
}

stock bool:is_float_text(const text[])
{
    if (text[0] == 0)
    {
        return false;
    }

    new start = 0;
    new bool:has_digit = false;
    new bool:has_dot = false;

    if (text[0] == '-')
    {
        start = 1;
    }

    for (new i = start; text[i] != 0; i++)
    {
        if (text[i] == '.')
        {
            if (has_dot)
            {
                return false;
            }

            has_dot = true;
            continue;
        }

        if (text[i] < '0' || text[i] > '9')
        {
            return false;
        }

        has_digit = true;
    }

    return has_digit;
}

stock reset_round_snapshot()
{
    g_round_snapshot_valid = false;
    g_round_winner = TEAM_NONE;

    for (new id = 1; id <= MAX_CLIENTS; id++)
    {
        reset_round_player(id);
    }
}

stock reset_round_player(id)
{
    if (id < 1 || id > MAX_CLIENTS)
    {
        return;
    }

    g_round_eligible[id] = false;
    g_round_team[id] = TEAM_NONE;
    g_round_elo[id] = 0;
    g_round_elo_cents[id] = 0;
    g_round_kills[id] = 0;
    g_round_deaths[id] = 0;
    g_round_damage[id] = 0;
    g_round_plants[id] = 0;
    g_round_defuses[id] = 0;
    g_round_teamkills[id] = 0;
    g_round_suicides[id] = 0;
    g_round_clutch[id] = 0;
    g_round_mvp[id] = false;
}

stock reset_player_memory(id)
{
    if (id < 1 || id > MAX_CLIENTS)
    {
        return;
    }

    g_loaded[id] = false;
    g_authid[id][0] = 0;
    g_saved_name[id][0] = 0;
    g_clean_name[id][0] = 0;
    g_tag_lock[id] = false;
    g_elo[id] = 0;
    g_elo_cents[id] = 0;
    g_ranked_rounds[id] = 0;
    g_wins[id] = 0;
    g_losses[id] = 0;
    g_highest_elo[id] = 0;
    g_last_seen[id] = 0;
    g_daily_day[id] = 0;
    g_daily_gain[id] = 0;
    g_daily_gain_cents[id] = 0;
    g_placement_target_sum[id] = 0.0;
    g_placement_weight_sum[id] = 0.0;
    g_session_delta[id] = 0;
    g_session_gain[id] = 0;
    g_session_delta_cents[id] = 0;
    g_session_gain_cents[id] = 0;
    g_session_placement_target_sum[id] = 0.0;
    g_session_placement_weight_sum[id] = 0.0;
    g_session_rounds[id] = 0;
    g_session_wins[id] = 0;
    g_session_losses[id] = 0;
}

stock sanitize_name(name[], len)
{
    replace_all(name, len, " ", "_");
    replace_all(name, len, "^"", "'");
    replace_all(name, len, ";", ".");
    replace_all(name, len, "|", "_");
    replace_all(name, len, "<", "_");
    replace_all(name, len, ">", "_");
    trim(name);
}

stock html_escape(const input[], output[], output_len)
{
    if (output_len < 1)
    {
        return;
    }

    new write_pos = 0;

    for (new read_pos = 0; input[read_pos] != 0 && write_pos < output_len - 1; read_pos++)
    {
        switch (input[read_pos])
        {
            case '&':
            {
                append_html_entity(output, output_len, write_pos, "&amp;");
            }
            case '<':
            {
                append_html_entity(output, output_len, write_pos, "&lt;");
            }
            case '>':
            {
                append_html_entity(output, output_len, write_pos, "&gt;");
            }
            case 34:
            {
                append_html_entity(output, output_len, write_pos, "&quot;");
            }
            default:
            {
                output[write_pos] = input[read_pos];
                write_pos++;
            }
        }
    }

    output[write_pos] = 0;
}

stock append_html_entity(output[], output_len, &write_pos, const entity[])
{
    for (new i = 0; entity[i] != 0 && write_pos < output_len - 1; i++)
    {
        output[write_pos] = entity[i];
        write_pos++;
    }
}

stock format_delta(delta, output[], output_len)
{
    if (delta >= 0)
    {
        formatex(output, output_len, "+%d", delta);
        return;
    }

    formatex(output, output_len, "%d", delta);
}

stock set_elo_cents(id, elo_cents)
{
    if (elo_cents < 0)
    {
        elo_cents = 0;
    }

    g_elo_cents[id] = elo_cents;
    g_elo[id] = cents_to_elo_floor(elo_cents);
}

stock elo_to_cents(elo)
{
    return elo * ELO_SCALE;
}

stock cents_to_elo_floor(elo_cents)
{
    if (elo_cents <= 0)
    {
        return 0;
    }

    return elo_cents / ELO_SCALE;
}

stock cents_to_elo_trunc(elo_cents)
{
    return elo_cents / ELO_SCALE;
}

stock clamp_elo_cents_to_placement(elo_cents)
{
    new min_cents = elo_to_cents(get_pcvar_num(g_cvar_placement_min_elo));
    new max_cents = elo_to_cents(get_pcvar_num(g_cvar_placement_max_elo));
    new hard_max_cents = elo_to_cents(2000);

    if (min_cents < 0)
    {
        min_cents = elo_to_cents(800);
    }

    if (max_cents < min_cents)
    {
        max_cents = hard_max_cents;
    }

    if (max_cents > hard_max_cents)
    {
        max_cents = hard_max_cents;
    }

    if (elo_cents < min_cents)
    {
        return min_cents;
    }

    if (elo_cents > max_cents)
    {
        return max_cents;
    }

    return elo_cents;
}

stock format_elo_cents(elo_cents, output[], output_len)
{
    if (!get_pcvar_num(g_cvar_decimal_display))
    {
        formatex(output, output_len, "%d", cents_to_elo_floor(elo_cents));
        return;
    }

    new abs_cents = elo_cents;
    new sign[2];

    if (abs_cents < 0)
    {
        abs_cents = -abs_cents;
        copy(sign, charsmax(sign), "-");
    }
    else
    {
        sign[0] = 0;
    }

    formatex(output, output_len, "%s%d.%02d", sign, abs_cents / ELO_SCALE, abs_cents % ELO_SCALE);
}

stock format_delta_cents(delta_cents, output[], output_len)
{
    if (!get_pcvar_num(g_cvar_decimal_display))
    {
        format_delta(cents_to_elo_trunc(delta_cents), output, output_len);
        return;
    }

    new abs_cents = delta_cents;
    new sign[2];

    if (abs_cents < 0)
    {
        abs_cents = -abs_cents;
        copy(sign, charsmax(sign), "-");
    }
    else
    {
        copy(sign, charsmax(sign), "+");
    }

    formatex(output, output_len, "%s%d.%02d", sign, abs_cents / ELO_SCALE, abs_cents % ELO_SCALE);
}

stock log_elo_round_skip(const reason[])
{
    if (!get_pcvar_num(g_cvar_log_enabled))
    {
        return;
    }

    log_to_file("savekai_elo.log", "Round skipped: %s | winner=%d | mode=%d", reason, g_round_winner, get_savekai_current_mode());
}

stock log_winner_detected(const winner[])
{
    if (!get_pcvar_num(g_cvar_log_enabled))
    {
        return;
    }

    new map_name[32];
    get_mapname(map_name, charsmax(map_name));

    log_to_file("savekai_elo.log", "Winner detected: %s | map=%s | mode=%d", winner, map_name, get_savekai_current_mode());
}

stock bool:is_chat_command(const args[], const command[])
{
    new command_len = strlen(command);

    if (equali(args, command))
    {
        return true;
    }

    if (!equali(args, command, command_len))
    {
        return false;
    }

    return args[command_len] == ' ';
}

stock strip_elo_tags(name[], len)
{
    new output[NAME_LEN];
    new write_pos = 0;

    for (new read_pos = 0; name[read_pos] != 0 && write_pos < charsmax(output);)
    {
        if (is_elo_tag_at(name, read_pos))
        {
            while (name[read_pos] != 0 && name[read_pos] != ']')
            {
                read_pos++;
            }

            if (name[read_pos] == ']')
            {
                read_pos++;
            }

            if (name[read_pos] == ' ')
            {
                read_pos++;
            }

            continue;
        }

        output[write_pos++] = name[read_pos++];
    }

    output[write_pos] = 0;
    copy(name, len, output);

    replace_all(name, len, "  ", " ");
    trim(name);
}

stock bool:is_elo_tag_at(const name[], pos)
{
    if (name[pos] != '[')
    {
        return false;
    }

    if (is_specific_elo_tag_at(name, pos, "SGM") ||
        is_specific_elo_tag_at(name, pos, "SIM") ||
        is_specific_elo_tag_at(name, pos, "SM") ||
        is_specific_elo_tag_at(name, pos, "G") ||
        is_specific_elo_tag_at(name, pos, "V") ||
        is_specific_elo_tag_at(name, pos, "P") ||
        is_specific_elo_tag_at(name, pos, "N") ||
        is_specific_elo_tag_at(name, pos, "U"))
    {
        return true;
    }

    return false;
}

stock bool:is_specific_elo_tag_at(const name[], pos, const tag[])
{
    new tag_len = strlen(tag);

    for (new i = 0; i < tag_len; i++)
    {
        if (name[pos + 1 + i] != tag[i])
        {
            return false;
        }
    }

    new next = name[pos + 1 + tag_len];
    return next == ']' || next == ' ';
}

stock get_clean_user_name(id, output[], output_len)
{
    if (id >= 1 && id <= MAX_CLIENTS && g_clean_name[id][0] != 0)
    {
        copy(output, output_len, g_clean_name[id]);
        return;
    }

    get_user_name(id, output, output_len);
    strip_elo_tags(output, output_len);
}

stock get_elo_scoreboard_tag(id, output[], output_len)
{
    output[0] = 0;

    if (!g_loaded[id])
    {
        return;
    }

    if (is_placement_round_count(g_ranked_rounds[id]))
    {
        return;
    }

    new elo = g_elo[id];
    new title[8];

    if (elo >= 2600)
    {
        copy(title, charsmax(title), "SGM");
    }
    else if (elo >= 2400)
    {
        copy(title, charsmax(title), "SIM");
    }
    else if (elo >= 2200)
    {
        copy(title, charsmax(title), "SM");
    }
    else
    {
        if (get_pcvar_num(g_cvar_scoreboard_titles_only))
        {
            return;
        }

        if (elo >= 1800)
        {
            copy(title, charsmax(title), "G");
        }
        else if (elo >= 1400)
        {
            copy(title, charsmax(title), "V");
        }
        else if (elo >= 1000)
        {
            copy(title, charsmax(title), "P");
        }
        else
        {
            copy(title, charsmax(title), "N");
        }
    }

    if (get_pcvar_num(g_cvar_scoreboard_show_exact))
    {
        formatex(output, output_len, "[%s %d]", title, elo);
        return;
    }

    formatex(output, output_len, "[%s]", title);
}

stock update_scoreboard_tag(id)
{
    if (id < 1 || id > MAX_CLIENTS || !is_user_connected(id) || is_user_bot(id) || is_user_hltv(id))
    {
        return;
    }

    if (g_clean_name[id][0] == 0)
    {
        new captured[NAME_LEN];
        get_user_name(id, captured, charsmax(captured));
        strip_elo_tags(captured, charsmax(captured));
        copy(g_clean_name[id], NAME_LEN - 1, captured);
    }

    new full[NAME_LEN];
    copy(full, charsmax(full), g_clean_name[id]);

    if (g_loaded[id] && get_pcvar_num(g_cvar_scoreboard_tags))
    {
        new tag[24];
        get_elo_scoreboard_tag(id, tag, charsmax(tag));

        if (tag[0] != 0)
        {
            formatex(full, charsmax(full), "%s %s", g_clean_name[id], tag);
        }
    }

    if (full[0] == 0)
    {
        return;
    }

    new current[NAME_LEN];
    get_user_name(id, current, charsmax(current));

    if (equal(current, full))
    {
        return;
    }

    g_tag_lock[id] = true;
    set_user_info(id, "name", full);
    g_tag_lock[id] = false;
}

stock refresh_all_scoreboard_tags()
{
    for (new id = 1; id <= MAX_CLIENTS; id++)
    {
        if (is_user_connected(id) && !is_user_bot(id) && !is_user_hltv(id))
        {
            update_scoreboard_tag(id);
        }
    }
}
