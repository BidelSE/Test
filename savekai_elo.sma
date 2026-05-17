/*
 * savekai_elo.sma
 *
 * SAVEKAI ELO system.
 * AMX Mod X 1.10 compatible.
 *
 * Version 0.6 goals:
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
#define PLUGIN_VERSION "0.6"
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

new g_vault = INVALID_VAULT;

new bool:g_loaded[MAX_CLIENTS + 1];
new g_authid[MAX_CLIENTS + 1][AUTH_LEN];
new g_saved_name[MAX_CLIENTS + 1][NAME_LEN];
new g_elo[MAX_CLIENTS + 1];
new g_ranked_rounds[MAX_CLIENTS + 1];
new g_wins[MAX_CLIENTS + 1];
new g_losses[MAX_CLIENTS + 1];
new g_highest_elo[MAX_CLIENTS + 1];
new g_last_seen[MAX_CLIENTS + 1];
new g_daily_day[MAX_CLIENTS + 1];
new g_daily_gain[MAX_CLIENTS + 1];
new Float:g_placement_target_sum[MAX_CLIENTS + 1];
new Float:g_placement_weight_sum[MAX_CLIENTS + 1];

new g_session_delta[MAX_CLIENTS + 1];
new g_session_gain[MAX_CLIENTS + 1];
new Float:g_session_placement_target_sum[MAX_CLIENTS + 1];
new Float:g_session_placement_weight_sum[MAX_CLIENTS + 1];
new g_session_rounds[MAX_CLIENTS + 1];
new g_session_wins[MAX_CLIENTS + 1];
new g_session_losses[MAX_CLIENTS + 1];

new bool:g_round_eligible[MAX_CLIENTS + 1];
new g_round_team[MAX_CLIENTS + 1];
new g_round_elo[MAX_CLIENTS + 1];
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
new g_cvar_min_leaderboard_rounds;
new g_cvar_k_placement;
new g_cvar_k_provisional;
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
new g_cvar_max_team_diff;
new g_cvar_min_team_players;
new g_cvar_daily_softcap_enabled;
new g_cvar_daily_softcap_1;
new g_cvar_daily_softcap_2;
new g_cvar_daily_softcap_3;
new g_cvar_daily_mult_1;
new g_cvar_daily_mult_2;
new g_cvar_daily_mult_3;
new g_cvar_daily_mult_4;
new g_cvar_current_mode;

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
    g_cvar_placement_win_shift = register_cvar("savekai_elo_placement_win_shift", "150.0");
    g_cvar_placement_loss_shift = register_cvar("savekai_elo_placement_loss_shift", "150.0");
    g_cvar_placement_perf_scale = register_cvar("savekai_elo_placement_perf_scale", "150.0");
    g_cvar_placement_max_above_enemy = register_cvar("savekai_elo_placement_max_above_enemy", "300.0");
    g_cvar_placement_max_below_enemy = register_cvar("savekai_elo_placement_max_below_enemy", "300.0");
    g_cvar_min_leaderboard_rounds = register_cvar("savekai_elo_min_leaderboard_rounds", "50");
    g_cvar_k_placement = register_cvar("savekai_elo_k_placement", "6.0");
    g_cvar_k_provisional = register_cvar("savekai_elo_k_provisional", "5.0");
    g_cvar_k_normal = register_cvar("savekai_elo_k_normal", "4.0");
    g_cvar_k_2200 = register_cvar("savekai_elo_k_2200", "3.0");
    g_cvar_k_2400 = register_cvar("savekai_elo_k_2400", "2.0");
    g_cvar_k_2600 = register_cvar("savekai_elo_k_2600", "1.5");
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
    g_cvar_testmode = register_cvar("savekai_elo_testmode", "1");
    g_cvar_testmode_save_placement = register_cvar("savekai_elo_testmode_save_placement", "1");
    g_cvar_disable_non_normal_mode = register_cvar("savekai_elo_disable_non_normal_mode", "1");
    g_cvar_override_rank = register_cvar("savekai_elo_override_rank", "0");
    g_cvar_show_round_delta = register_cvar("savekai_elo_show_round_delta", "1");
    g_cvar_debug_chat = register_cvar("savekai_elo_debug_chat", "1");
    g_cvar_max_team_diff = register_cvar("savekai_elo_max_team_diff", "2");
    g_cvar_min_team_players = register_cvar("savekai_elo_min_team_players", "2");
    g_cvar_daily_softcap_enabled = register_cvar("savekai_elo_daily_softcap_enabled", "1");
    g_cvar_daily_softcap_1 = register_cvar("savekai_elo_daily_softcap_1", "50");
    g_cvar_daily_softcap_2 = register_cvar("savekai_elo_daily_softcap_2", "100");
    g_cvar_daily_softcap_3 = register_cvar("savekai_elo_daily_softcap_3", "150");
    g_cvar_daily_mult_1 = register_cvar("savekai_elo_daily_mult_1", "1.00");
    g_cvar_daily_mult_2 = register_cvar("savekai_elo_daily_mult_2", "0.50");
    g_cvar_daily_mult_3 = register_cvar("savekai_elo_daily_mult_3", "0.25");
    g_cvar_daily_mult_4 = register_cvar("savekai_elo_daily_mult_4", "0.10");

    register_clcmd("say", "hook_say");
    register_clcmd("say_team", "hook_say");

    register_concmd("amx_elo", "concmd_elo", ADMIN_RCON, "<player>");
    register_concmd("amx_setelo", "concmd_setelo", ADMIN_RCON, "<player> <amount>");
    register_concmd("amx_resetelo", "concmd_resetelo", ADMIN_RCON, "<player>");
    register_concmd("amx_giveelo", "concmd_giveelo", ADMIN_RCON, "<player> <amount>");
    register_concmd("amx_takeelo", "concmd_takeelo", ADMIN_RCON, "<player> <amount>");
    register_concmd("amx_eloreload", "concmd_eloreload", ADMIN_RCON, "reload SAVEKAI ELO data");

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
    format_delta(g_session_delta[id], delta_text, charsmax(delta_text));

    client_print(id, print_chat, "[SAVEKAI ELO] Session: %s ELO | Gain: +%d | Roundai: %d | W/L: %d/%d",
        delta_text,
        g_session_gain[id],
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

    new start_elo = get_start_elo();
    g_elo[target] = start_elo;
    g_ranked_rounds[target] = 0;
    g_wins[target] = 0;
    g_losses[target] = 0;
    g_highest_elo[target] = start_elo;
    g_daily_day[target] = get_current_day();
    g_daily_gain[target] = 0;
    g_placement_target_sum[target] = 0.0;
    g_placement_weight_sum[target] = 0.0;
    g_session_delta[target] = 0;
    g_session_gain[target] = 0;
    g_session_placement_target_sum[target] = 0.0;
    g_session_placement_weight_sum[target] = 0.0;
    g_session_rounds[target] = 0;
    g_session_wins[target] = 0;
    g_session_losses[target] = 0;

    save_player(target, true);
    announce_admin_change(id, target, "reset", start_elo, 0);
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
    new t_sum, ct_sum;

    for (new id = 1; id <= MAX_CLIENTS; id++)
    {
        if (!is_round_player_valid(id))
        {
            log_round_player_skip_if_needed(id);
            continue;
        }

        total_count++;

        if (g_round_team[id] == TEAM_T)
        {
            t_count++;
            t_sum += g_round_elo[id];
        }
        else if (g_round_team[id] == TEAM_CT)
        {
            ct_count++;
            ct_sum += g_round_elo[id];
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
    new max_team_diff = get_max_team_diff();

    if (max_team_diff >= 0 && team_diff > max_team_diff)
    {
        log_elo_round_skip("team size difference too high");
        reset_round_snapshot();
        return;
    }

    new Float:t_avg = float(t_sum) / float(t_count);
    new Float:ct_avg = float(ct_sum) / float(ct_count);
    new Float:map_multiplier = get_map_multiplier();
    new Float:player_multiplier = get_player_count_multiplier(total_count);
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
    get_mapname(map_name, charsmax(map_name));

    if (get_pcvar_num(g_cvar_log_enabled))
    {
        log_to_file("savekai_elo.log",
            "Round map=%s mode=%d winner=%s total=%d T=%d CT=%d T_avg=%.1f CT_avg=%.1f map_mult=%.2f player_mult=%.2f testmode=%d",
            map_name,
            get_savekai_current_mode(),
            winner_text,
            total_count,
            t_count,
            ct_count,
            t_avg,
            ct_avg,
            map_multiplier,
            player_multiplier,
            testmode ? 1 : 0
        );
    }

    mark_round_mvp();

    for (new id = 1; id <= MAX_CLIENTS; id++)
    {
        if (!is_round_player_valid(id))
        {
            continue;
        }

        apply_round_delta(id, t_avg, ct_avg, map_multiplier, player_multiplier, testmode);
    }

    reset_round_snapshot();
}

stock apply_round_delta(id, Float:t_avg, Float:ct_avg, Float:map_multiplier, Float:player_multiplier, bool:testmode)
{
    new old_elo = g_elo[id];
    new team = g_round_team[id];
    new bool:won = team == g_round_winner;
    new bool:placement = is_in_placement(id);
    new bool:save_test_placement = should_save_testmode_placement(placement, testmode);

    new Float:own_avg = team == TEAM_T ? t_avg : ct_avg;
    new Float:enemy_avg = team == TEAM_T ? ct_avg : t_avg;
    new Float:expected = calculate_expected_score(own_avg, enemy_avg);
    new Float:result = won ? 1.0 : 0.0;
    new Float:k = get_k_coefficient(old_elo, g_ranked_rounds[id]);
    new Float:base_delta = k * (result - expected);
    new Float:perf_delta = get_performance_modifier(id, placement);
    new Float:placement_weight = map_multiplier * player_multiplier;
    new Float:raw_delta = (base_delta + perf_delta) * map_multiplier * player_multiplier;
    new delta = floatround(raw_delta);
    new before_softcap = delta;
    new Float:daily_multiplier = 1.0;
    new placement_target = 0;

    if (placement_weight < 0.0)
    {
        placement_weight = 0.0;
    }

    delta = cap_round_delta(delta);
    delta = apply_win_loss_bounds(won, delta);
    delta = apply_daily_softcap(id, delta, daily_multiplier);

    new new_elo = old_elo + delta;

    if (placement)
    {
        placement_target = calculate_placement_target(enemy_avg, won, perf_delta);
        new_elo = calculate_placement_estimate(id, placement_target, placement_weight, testmode && !save_test_placement);
    }
    else if (new_elo < 0)
    {
        new_elo = 0;
    }

    g_session_delta[id] += delta;
    if (delta > 0)
    {
        g_session_gain[id] += delta;
        update_daily_gain(id, delta);
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

        g_elo[id] = new_elo;

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

    print_round_delta(id, old_elo, new_elo, delta, expected, k, perf_delta, placement, testmode);
    log_round_delta(id, old_elo, new_elo, delta, before_softcap, expected, k, base_delta, perf_delta, daily_multiplier, placement, placement_target, placement_weight, testmode);
}

stock print_round_delta(id, old_elo, new_elo, delta, Float:expected, Float:k, Float:perf_delta, bool:placement, bool:testmode)
{
    if (!get_pcvar_num(g_cvar_show_round_delta))
    {
        return;
    }

    new delta_text[16];
    new old_rank[48], new_rank[48];
    format_delta(delta, delta_text, charsmax(delta_text));
    get_rank_title_by_elo(old_elo, old_rank, charsmax(old_rank));
    get_rank_title_by_elo(new_elo, new_rank, charsmax(new_rank));

    if (testmode)
    {
        client_print(id, print_chat, "[SAVEKAI ELO] Test mode: %s ELO butu pritaikyta, bet nesaugoma.", delta_text);

        if (get_pcvar_num(g_cvar_debug_chat))
        {
            client_print(id, print_chat, "[SAVEKAI ELO] Old %d -> New %d | Exp %.2f | K %.1f | Perf %.2f", old_elo, new_elo, expected, k, perf_delta);
        }

        if (placement)
        {
            new placement_rounds = g_ranked_rounds[id];

            if (!get_pcvar_num(g_cvar_testmode_save_placement))
            {
                placement_rounds += g_session_rounds[id];
            }

            client_print(id, print_chat, "[SAVEKAI ELO] Placement estimate: %d/%d roundu.",
                placement_rounds,
                get_placement_rounds()
            );
        }

        return;
    }

    client_print(id, print_chat, "[SAVEKAI ELO] %s ELO | %s -> %s",
        delta_text,
        old_rank,
        new_rank
    );

    if (get_pcvar_num(g_cvar_debug_chat))
    {
        client_print(id, print_chat, "[SAVEKAI ELO] Old %d -> New %d | Exp %.2f | K %.1f | Perf %.2f", old_elo, new_elo, expected, k, perf_delta);
    }
}

stock log_round_delta(id, old_elo, new_elo, delta, before_softcap, Float:expected, Float:k, Float:base_delta, Float:perf_delta, Float:daily_multiplier, bool:placement, placement_target, Float:placement_weight, bool:testmode)
{
    if (!get_pcvar_num(g_cvar_log_enabled))
    {
        return;
    }

    new name[NAME_LEN], delta_text[16], old_rank[48], new_rank[48];
    new team_text[4];
    get_user_name(id, name, charsmax(name));
    sanitize_name(name, charsmax(name));
    format_delta(delta, delta_text, charsmax(delta_text));
    get_rank_title_by_elo(old_elo, old_rank, charsmax(old_rank));
    get_rank_title_by_elo(new_elo, new_rank, charsmax(new_rank));

    if (g_round_team[id] == TEAM_T)
    {
        copy(team_text, charsmax(team_text), "T");
    }
    else
    {
        copy(team_text, charsmax(team_text), "CT");
    }

    log_to_file("savekai_elo.log",
        "%s auth=%s team=%s old=%d new=%d delta=%s before_softcap=%d expected=%.2f k=%.1f base=%.2f perf=%.2f daily_mult=%.2f placement=%d placement_target=%d placement_weight=%.2f kills=%d deaths=%d damage=%d mvp=%d plant=%d defuse=%d tk=%d suicide=%d clutch=%d old_rank=%s new_rank=%s testmode=%d",
        name,
        g_authid[id],
        team_text,
        old_elo,
        new_elo,
        delta_text,
        before_softcap,
        expected,
        k,
        base_delta,
        perf_delta,
        daily_multiplier,
        placement ? 1 : 0,
        placement_target,
        placement_weight,
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
        testmode ? 1 : 0
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

    if (ranked_rounds < 100)
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

stock update_daily_gain(id, delta)
{
    if (delta <= 0)
    {
        return;
    }

    refresh_daily_window(id);
    g_daily_gain[id] += delta;
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
    g_elo[id] = start_elo;
    g_ranked_rounds[id] = 0;
    g_wins[id] = 0;
    g_losses[id] = 0;
    g_highest_elo[id] = start_elo;
    g_last_seen[id] = get_systime();
    g_daily_day[id] = get_current_day();
    g_daily_gain[id] = 0;
    g_placement_target_sum[id] = 0.0;
    g_placement_weight_sum[id] = 0.0;

    new name[NAME_LEN];
    get_user_name(id, name, charsmax(name));
    sanitize_name(name, charsmax(name));
    copy(g_saved_name[id], NAME_LEN - 1, name);

    if (g_vault != INVALID_VAULT)
    {
        new loaded_name[NAME_LEN], elo, rounds, wins, losses, highest, last_seen, daily_day, daily_gain;
        new Float:placement_sum, Float:placement_weight;

        if (load_elo_by_authid(g_authid[id], elo, rounds, wins, losses, highest, loaded_name, charsmax(loaded_name), last_seen, daily_day, daily_gain, placement_sum, placement_weight))
        {
            g_elo[id] = elo;
            g_ranked_rounds[id] = rounds;
            g_wins[id] = wins;
            g_losses[id] = losses;
            g_highest_elo[id] = highest > 0 ? highest : elo;
            g_last_seen[id] = last_seen;
            g_daily_day[id] = daily_day;
            g_daily_gain[id] = daily_gain;
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

    add_authid_to_slots(g_authid[id]);

    new name[NAME_LEN];
    get_user_name(id, name, charsmax(name));
    sanitize_name(name, charsmax(name));

    if (name[0] != 0)
    {
        copy(g_saved_name[id], NAME_LEN - 1, name);
    }

    new key[64], data[DATA_LEN];
    formatex(key, charsmax(key), "elo:%s", g_authid[id]);
    refresh_daily_window(id);
    formatex(data, charsmax(data), "%d %d %d %d %d %d %d %d %.3f %.3f %s",
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

stock bool:load_elo_by_authid(const authid[], &elo, &rounds, &wins, &losses, &highest, name[], name_len, &last_seen, &daily_day, &daily_gain, &Float:placement_sum, &Float:placement_weight)
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
    new title[48];
    get_rank_title(g_elo[target], g_ranked_rounds[target], title, charsmax(title));

    client_print(receiver, print_chat, "[SAVEKAI ELO] Tavo ELO: %d | Rank: %s | Roundai: %d",
        g_elo[target],
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
        client_print(receiver, print_chat, "[SAVEKAI ELO] Placement estimate: %d/%d roundu. Min: %d.",
            g_ranked_rounds[target],
            get_placement_rounds(),
            get_placement_min_rounds()
        );
    }

    refresh_daily_window(target);
    client_print(receiver, print_chat, "[SAVEKAI ELO] Daily gain: +%d | Leaderboard nuo %d roundu.",
        get_effective_daily_gain(target),
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
    new name[NAME_LEN], title[48];
    get_user_name(target, name, charsmax(name));
    get_rank_title(g_elo[target], g_ranked_rounds[target], title, charsmax(title));

    console_print(admin, "[SAVEKAI ELO] %s | ELO %d | Rank %s | Rounds %d | W/L %d/%d | Highest %d",
        name,
        g_elo[target],
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
    new bool:testmode = get_pcvar_num(g_cvar_testmode) != 0;
    new top_elo[TOP_SIZE];
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

        new name[NAME_LEN], elo, rounds, wins, losses, highest, last_seen, daily_day, daily_gain;
        new Float:placement_sum, Float:placement_weight;

        if (!load_elo_by_authid(authid, elo, rounds, wins, losses, highest, name, charsmax(name), last_seen, daily_day, daily_gain, placement_sum, placement_weight))
        {
            continue;
        }

        if (rounds < min_rounds)
        {
            continue;
        }

        insert_topelo_candidate(name, elo, rounds, top_elo, top_rounds, top_name);
    }

    new shown = 0;

    for (new i = 0; i < TOP_SIZE; i++)
    {
        if (top_elo[i] <= 0)
        {
            continue;
        }

        new safe_name[NAME_LEN * 2], title[48];
        html_escape(top_name[i], safe_name, charsmax(safe_name));
        get_rank_title_by_elo(top_elo[i], title, charsmax(title));

        len += formatex(motd[len], charsmax(motd) - len,
            "<tr><td>%d</td><td>%s</td><td>%d</td><td>%d</td><td>%s</td></tr>",
            i + 1,
            safe_name,
            top_elo[i],
            top_rounds[i],
            title
        );
        shown++;
    }

    if (!shown)
    {
        if (testmode)
        {
            len += formatex(motd[len], charsmax(motd) - len,
                "<tr><td colspan=5>Testmode is ON, so official leaderboard data is not saved yet.</td></tr>"
            );
        }
        else
        {
            len += formatex(motd[len], charsmax(motd) - len,
                "<tr><td colspan=5>No players with %d+ ranked rounds yet.</td></tr>",
                min_rounds
            );
        }
    }

    new testmode_text[4];

    if (testmode)
    {
        copy(testmode_text, charsmax(testmode_text), "ON");
    }
    else
    {
        copy(testmode_text, charsmax(testmode_text), "OFF");
    }

    formatex(motd[len], charsmax(motd) - len, "</table><p>Testmode: %s</p></body></html>",
        testmode_text
    );

    show_motd(id, motd, "SAVEKAI Top ELO");
}

stock insert_topelo_candidate(const name[], elo, rounds, top_elo[], top_rounds[], top_name[][NAME_LEN])
{
    for (new pos = 0; pos < TOP_SIZE; pos++)
    {
        if (elo <= top_elo[pos])
        {
            continue;
        }

        for (new move = TOP_SIZE - 1; move > pos; move--)
        {
            top_elo[move] = top_elo[move - 1];
            top_rounds[move] = top_rounds[move - 1];
            copy(top_name[move], NAME_LEN - 1, top_name[move - 1]);
        }

        top_elo[pos] = elo;
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
    g_elo[target] = new_elo;

    if (g_elo[target] > g_highest_elo[target])
    {
        g_highest_elo[target] = g_elo[target];
    }

    save_player(target, true);
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
    g_elo[id] = 0;
    g_ranked_rounds[id] = 0;
    g_wins[id] = 0;
    g_losses[id] = 0;
    g_highest_elo[id] = 0;
    g_last_seen[id] = 0;
    g_daily_day[id] = 0;
    g_daily_gain[id] = 0;
    g_placement_target_sum[id] = 0.0;
    g_placement_weight_sum[id] = 0.0;
    g_session_delta[id] = 0;
    g_session_gain[id] = 0;
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
