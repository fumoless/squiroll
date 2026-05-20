// data/script/takeover.nut
// ============================================================
// 录像快进 → 指定帧接管
//
// 快进分两阶段：
//   Phase 1 (开场动画帧): state!=8，只消费录像输入，不执行战斗逻辑
//   Phase 2 (战斗帧):     state==8，完整执行 UpdateMain 逻辑
//
// intro_frames 的精确计算依赖 time_initial：
//   time_initial 由 battle_update.nut 在 state 首次变为 8 时记录
//   intro_frames = saved_frame - (time_initial - saved_time)
//   battle_frames = time_initial - saved_time
//   合计 = saved_frame ✓
// ============================================================

active <- false;
saved_frame <- null;
saved_time <- null;
saved_state <- null;
time_initial <- null;   // 由 battle_update.nut 在 state 首次==8 时写入
battle_start_count <- null;  // 【新增】战斗开始时的 count 值，用于精确计算 battle_frames

// ============================================================
// Save
// ============================================================
function Save() {
    saved_frame = ::battle.count;
    saved_time  = ::battle.time;
    saved_state = ::battle.state;

    ::print("[Takeover] Marked frame " + saved_frame
        + " (time=" + saved_time + ", state=" + saved_state
        + ", time_initial=" + time_initial + ")\n");
}

// ============================================================
// Load
//   replay_mode = true  : 继续放录像，不切换到玩家操作
//   replay_mode = false : 切换指定玩家为操作（默认）
//   player_index = 0    : 接管P1（默认）
//   player_index = 1    : 接管P2
// ============================================================
function Load(replay_mode = false, player_index = 0) {
    if (saved_frame == null) {
        ::print("[Takeover] No frame marked.\n");
        return;
    }
    if (time_initial == null) {
        ::print("[Takeover] ERROR: time_initial not yet recorded. "
            + "Play until battle starts (state=8) before loading.\n");
        return;
    }

    local target_frame = saved_frame;

    // ----------------------------------------------------------
    // 1. 计算两阶段帧数
    //
    // 【分析】
    // - team.Update() 在时停判断之前被调用，所以每帧都消费录像输入
    // - time 只在非时停帧减少
    // - count 每帧都增加
    //
    // 因此：
    // - 录像输入消费数 = count 差值
    // - time 差值 = 非时停帧数
    //
    // 我们需要消费的录像输入数 = count 差值
    // 所以应该用 count 来计算，而不是 time
    // ----------------------------------------------------------
    local battle_frames;
    local intro_frames;
    local time_based_frames = time_initial - saved_time;

    if (battle_start_count != null) {
        // 使用 count 计算（准确反映录像输入消费数）
        //
        // 【关键修复】时序问题：
        // - battle_start_count 是 state 首次变为 8 那帧的 count 值
        // - 在那一帧，team.Update() 已经消费了第 battle_start_count 帧的录像输入
        // - 但 battle_start_count 的记录是在 team.Update() 之后、count++ 之前
        // - 所以正常流程中，从 state==8 开始到 Save 时消费的帧数是 (target_frame - battle_start_count + 1)
        // - 而不是 (target_frame - battle_start_count)
        //
        // 修正公式：
        //   intro_frames = battle_start_count - 1（消费帧 0 到 battle_start_count-2，少消费 1 帧）
        //   battle_frames = target_frame - battle_start_count + 1（多消费 1 帧）
        //
        battle_frames = target_frame - battle_start_count + 1;
        intro_frames = battle_start_count - 1;

        // 边界情况处理
        if (intro_frames < 0) {
            ::print("[Takeover] WARNING: intro_frames < 0, adjusting...\n");
            intro_frames = 0;
        }
        if (battle_frames < 0) {
            ::print("[Takeover] WARNING: battle_frames < 0, adjusting...\n");
            battle_frames = 0;
        }

        ::print("[Takeover] Using count-based calculation (with timing fix v2)\n");
    } else {
        // 回退
        battle_frames = time_based_frames;
        intro_frames = target_frame - battle_frames;
        ::print("[Takeover] WARNING: battle_start_count not available, using time\n");
    }

    if (intro_frames < 0) intro_frames = 0;
    if (battle_frames < 0) battle_frames = 0;

    ::print("[Takeover] Frame calculation:\n");
    ::print("[Takeover]   target_frame = " + target_frame + "\n");
    ::print("[Takeover]   time_initial = " + time_initial + ", saved_time = " + saved_time + "\n");
    ::print("[Takeover]   time-based battle_frames = " + time_based_frames + "\n");
    ::print("[Takeover]   battle_start_count = " + (battle_start_count != null ? battle_start_count : "null") + "\n");
    ::print("[Takeover]   count-based battle_frames (old formula) = " + (battle_start_count != null ? (target_frame - battle_start_count) : "N/A") + "\n");
    ::print("[Takeover]   count-based battle_frames (new formula v2) = " + (battle_start_count != null ? (target_frame - battle_start_count + 1) : "N/A") + "\n");
    ::print("[Takeover]   intro_frames = " + intro_frames + " (frames 0 to " + (intro_frames - 1) + ")\n");
    ::print("[Takeover]   battle_frames (final) = " + battle_frames + " (frames " + intro_frames + " to " + (intro_frames + battle_frames - 1) + ")\n");
    ::print("[Takeover]   Verify: " + intro_frames + " + " + battle_frames + " = " + (intro_frames + battle_frames) + "\n");

    // 检测时停
    if (battle_start_count != null) {
        local count_based = target_frame - battle_start_count;
        if (count_based != time_based_frames) {
            ::print("[Takeover] [INFO] Time-stop detected! count diff = "
                + (count_based - time_based_frames) + " frames\n");
        }
    }

    // 验证帧数计算
    local total_frames = intro_frames + battle_frames;
    if (total_frames != target_frame) {
        ::print("[Takeover] WARNING: frame count mismatch! "
            + intro_frames + " + " + battle_frames + " = " + total_frames
            + " != " + target_frame + "\n");
    }

    // ----------------------------------------------------------
    // 2. 重置角色到 round 初始状态
    // ----------------------------------------------------------
    local saved_battleUpdate = ::battle.battleUpdate;

    // 清理 group_player 和 group_effect 中的所有 shot/effect
    // 这是正常 RoundReset() 的做法，~15 是位掩码，保留主要的 player actor
    // 鹰等 Shot 对象存储在 group_player 中，需要这样清理
    try {
        ::battle.group_player.Clear(~15);
    } catch(e) {
        ::print("[Takeover] Warning: group_player.Clear failed: " + e + "\n");
    }
    try {
        ::battle.group_effect.Clear(-1);
    } catch(e) {}

    // 清理角色的附属对象引用（弱引用）
    foreach (team in ::battle.team) {
        local actors = [team.master, team.slave];
        foreach (actor in actors) {
            if (actor == null) continue;
            _ClearActorAttachments(actor);
        }
    }

    foreach (team in ::battle.team) {
        team.ResetRound();

        // 显式重置 centerY 为 start_y（ResetRound 不会重置这个值）
        local actors = [team.master, team.slave];
        foreach (actor in actors) {
            if (actor == null) continue;
            actor.centerY = ::battle.start_y[team.index];
        }
    }

    // 调试：打印重置后的状态
    foreach (i, team in ::battle.team) {
        local m = team.master;
        local s = team.slave;
        ::print("[Takeover] P" + (i+1) + " reset: "
            + "master(x=" + m.x + ", y=" + m.y + ", dir=" + m.direction
            + ", centerY=" + m.centerY + ", centerStop=" + m.centerStop + ")\n");
        if (s) {
            ::print("[Takeover] P" + (i+1) + " slave: "
                + "x=" + s.x + ", y=" + s.y + ", centerY=" + s.centerY + "\n");
        }
    }

    // 调用角色的 resetFunc 重新创建附属对象（如 Kasen 的鹰、Hijiri 的星星）
    foreach (team in ::battle.team) {
        local actors = [team.master, team.slave];
        foreach (actor in actors) {
            if (actor != null && "resetFunc" in actor && typeof actor.resetFunc == "function") {
                try {
                    actor.resetFunc();
                } catch (e) {
                    ::print("[Takeover] Warning: resetFunc failed for actor: " + e + "\n");
                }
            }
        }
    }

    // 清理其他列表
    local clear_targets = ["projectiles", "atoms", "items"];
    foreach (list_name in clear_targets) {
        if (list_name in ::battle) {
            local list = ::battle[list_name];
            for (local i = list.len() - 1; i >= 0; i--) {
                try {
                    if ("Release" in list[i]) list[i].Release();
                } catch(e) {}
            }
            list.clear();
        }
    }

    // ----------------------------------------------------------
    // 3. 重置战斗参数
    // ----------------------------------------------------------
    ::battle.count = 0;
    // time_initial 现在已经记录了 time-- 之前的值（在 battle_update.nut 中修正）
    ::battle.time = time_initial;
    ::battle.time_stop_count = 0;
    ::battle.slow_count = 0;
    ::battle.is_time_stop = false;
    ::battle.battleUpdate = saved_battleUpdate;
    ::battle.enableTimeCount = true;

    // ----------------------------------------------------------
    // 4. 双方输入接回录像，倒带到第 0 帧
    // ----------------------------------------------------------
    foreach (i, team in ::battle.team) {
        local replay_input = ::input.CreatePlayerInputDevice(team.index, team.device_id);

        if (::replay.recorder != null) {
            ::replay.recorder.SetDevice(team.index, replay_input);
            ::replay.recorder.BeginPlay(team.index);
        }

        team.input = replay_input;
        _SyncInputToActors(team);
    }

    // ----------------------------------------------------------
    // 5. Phase 1: 开场动画阶段
    //    state 设为 0，只消费录像输入帧，不执行战斗逻辑
    //    角色保持在开始位置不动（和原始对局一致）
    // ----------------------------------------------------------
    ::battle.state = 0;

    // 【调试】记录 Phase 1 开始前的录像设备位置（通过读取第一帧输入来判断）
    ::print("[Takeover] [DEBUG] Before Phase 1: P1 input.x=" + ::battle.team[0].input.x
        + ", P2 input.x=" + ::battle.team[1].input.x + "\n");

    for (local f = 0; f < intro_frames; f++) {
        foreach (v in ::battle.team) {
            v.Update();  // 同时更新 input 和 combo
        }
        ::battle.count++;
    }

    // 调试：Phase 1 结束后状态
    ::print("[Takeover] After Phase 1 (intro=" + intro_frames + " frames):\n");
    ::print("[Takeover] battle.count = " + ::battle.count + "\n");
    ::print("[Takeover] [DEBUG] After Phase 1: P1 input.x=" + ::battle.team[0].input.x
        + ", P2 input.x=" + ::battle.team[1].input.x + "\n");
    foreach (i, team in ::battle.team) {
        local m = team.master;
        local s = team.slave;
        ::print("  P" + (i+1) + ": motion=" + m.motion + ", x=" + m.x
            + ", y=" + m.y + ", dir=" + m.direction + "\n");
        ::print("  P" + (i+1) + " input: x=" + team.input.x + ", y=" + team.input.y
            + ", b0=" + team.input.b0 + ", b1=" + team.input.b1 + "\n");
    }

    // 关键修复：清空角色的输入缓冲区，防止 Phase 1 期间的输入影响 Phase 2
    foreach (team in ::battle.team) {
        local actors = [team.master, team.slave];
        foreach (actor in actors) {
            if (actor == null) continue;
            // 清空输入状态
            actor.input.x = 0;
            actor.input.y = 0;
            actor.input.b0 = 0;
            actor.input.b1 = 0;
            actor.input.b2 = 0;
            actor.input.b3 = 0;
            actor.input.b4 = 0;
            actor.input.b5 = 0;
            actor.input.b6 = 0;
            actor.input.b7 = 0;
            actor.input.b8 = 0;
            actor.input.b9 = 0;
            actor.input.b10 = 0;
            // 重置 command 缓冲区（包括输入历史）
            if (actor.command != null) {
                if ("Clear" in actor.command) {
                    actor.command.Clear();  // 清除 manbow.InputCommand 内部状态（输入历史缓冲区）
                }
                if ("ResetReserve" in actor.command) {
                    actor.command.ResetReserve();  // 清除预留输入
                }
                // 重置输入限制状态
                if ("ban_slide" in actor.command) actor.command.ban_slide = 0;
                if ("ban_b" in actor.command) actor.command.ban_b = 0;
            }
        }
    }

    // ----------------------------------------------------------
    // 6. Phase 2: 战斗阶段
    //    state 切到 8，完整执行战斗逻辑
    // ----------------------------------------------------------
    ::battle.state = 8;

    // 【调试】记录 Phase 2 开始时的输入状态
    ::print("[Takeover] [DEBUG] Before Phase 2: P1 input.x=" + ::battle.team[0].input.x
        + ", P2 input.x=" + ::battle.team[1].input.x + "\n");

    for (local f = 0; f < battle_frames; f++) {
        // 【调试】在第一帧和最后一帧打印输入
        if (f == 0 || f == battle_frames - 1) {
            ::print("[Takeover] [DEBUG] Phase 2 frame " + f + ": P1 input.x=" + ::battle.team[0].input.x
                + ", P2 input.x=" + ::battle.team[1].input.x + "\n");
        }
        _TickOneFrame();
        if (f == 0 || f == battle_frames - 1) {
            ::print("[Takeover] [DEBUG] After frame " + f + ": P1 input.x=" + ::battle.team[0].input.x
                + ", P2 input.x=" + ::battle.team[1].input.x + "\n");
        }
    }

    // 调试：Phase 2 结束后状态
    ::print("[Takeover] After Phase 2 (battle=" + battle_frames + " frames):\n");
    foreach (i, team in ::battle.team) {
        local m = team.master;
        local s = team.slave;
        ::print("  P" + (i+1) + ": motion=" + m.motion + ", x=" + m.x
            + ", y=" + m.y + ", dir=" + m.direction + "\n");
    }


    // 时间校验（理论上应该精确匹配）
    if (::battle.time != saved_time) {
        ::print("[Takeover] Time correction: " + ::battle.time + " -> " + saved_time + "\n");
        ::battle.time = saved_time;
    }

    ::print("[Takeover] Arrived at frame " + ::battle.count
        + " (time=" + ::battle.time + ", state=" + ::battle.state + ")\n");

    // ----------------------------------------------------------
    // 7. 切换指定玩家为实时输入（仅在非replay模式下）
    // ----------------------------------------------------------
    if (!replay_mode) {
        local team = ::battle.team[player_index];
        local my_device_id = -1;

        team.input = ::input.CreatePlayerInputDevice(team.index, my_device_id);
        _SyncInputToActors(team);

        if ("type" in team) team.type = 0;
        if ("cpu" in team) team.cpu = false;
        if ("auto" in team) team.auto = false;
        if ("controller" in team) team.controller = null;

        active = true;
        ::print("[Takeover] P" + (player_index + 1) + " is now live.\n");
    } else {
        // replay模式：保持录像输入，不做切换
        active = false;
        ::print("[Takeover] Replay mode - continuing with replay input.\n");
    }
}

// ============================================================
// 辅助：同步 team.input 到 master/slave
// ============================================================
function _SyncInputToActors(team) {
    local actors = [team.master, team.slave];
    foreach (actor in actors) {
        if (actor == null) continue;
        if ("input" in actor) actor.input = team.input;
        if ("command" in actor && actor.command) {
            if ("device" in actor.command)
                actor.command.device = team.input;
            if ("com" in actor.command && actor.command.com)
                actor.command.com.SetDevice(team.input);
        }
    }
}

// ============================================================
// 辅助：清理角色的附属对象（如 Kasen 的鹰、Hijiri 的星星等）
// ============================================================
function _ClearActorAttachments(actor) {
    // 辅助函数：安全释放对象（处理弱引用）
    local function _safeRelease(obj) {
        if (obj == null) return;
        // 如果是弱引用，尝试获取实际对象
        local realObj = obj;
        if (typeof obj == "weakref") {
            try {
                realObj = obj.weakref();
                // weakref() 在 squirrel 中返回的是弱引用对象本身
                // 要获取实际对象需要用 .value 或直接调用
            } catch (e) {}
        }
        // 尝试调用 Release
        try {
            if ("Release" in obj) {
                obj.Release();
            }
        } catch (e) {
            ::print("[Takeover] Release failed: " + e + "\n");
        }
    }

    // Kasen 的鹰 (eagle) - 这是一个 Shot 对象，通过 weakref 存储
    if ("eagle" in actor && actor.eagle != null) {
        try {
            // 直接在弱引用上调用 Release（Squirrel 会自动解引用）
            if ("Release" in actor.eagle) {
                actor.eagle.Release();
            }
        } catch (e) {
            ::print("[Takeover] Failed to release eagle: " + e + "\n");
        }
        actor.eagle = null;
    }

    // Hijiri 的星星 (chantCountBall)
    if ("chantCountBall" in actor && actor.chantCountBall != null) {
        foreach (ball in actor.chantCountBall) {
            if (ball != null) {
                try {
                    if ("Release" in ball) ball.Release();
                } catch (e) {}
            }
        }
        actor.chantCountBall = null;
    }

    // 其他可能的附属对象（通用处理）
    local attachment_names = [
        "dragon", "tiger", "seals", "ball",  // Kasen 的其他附属
        "byke",  // Hijiri 的自行车
        "occultAura",  // 部分角色的 occult aura
    ];

    foreach (name in attachment_names) {
        if (name in actor && actor[name] != null) {
            local obj = actor[name];
            if (typeof obj == "array") {
                foreach (item in obj) {
                    if (item != null) {
                        try {
                            if ("Release" in item) item.Release();
                        } catch (e) {}
                    }
                }
            } else {
                try {
                    if ("Release" in obj) obj.Release();
                } catch (e) {}
            }
            actor[name] = null;
        }
    }

    // 清理 option 数组（部分角色有）
    if ("option" in actor && typeof actor.option == "array") {
        for (local i = actor.option.len() - 1; i >= 0; i--) {
            local opt = actor.option[i];
            if (opt != null) {
                try {
                    if ("Release" in opt) opt.Release();
                } catch (e) {}
            }
        }
        actor.option.clear();
    }

    // 清理 linkObject 数组
    if ("linkObject" in actor && typeof actor.linkObject == "array") {
        for (local i = actor.linkObject.len() - 1; i >= 0; i--) {
            local obj = actor.linkObject[i];
            if (obj != null) {
                try {
                    if ("Release" in obj) obj.Release();
                } catch (e) {}
            }
        }
        actor.linkObject.clear();
    }
}

// ============================================================
// 辅助：执行一帧完整战斗逻辑（复刻 UpdateMain）
// ============================================================
function _TickOneFrame() {
    foreach (v in ::battle.team) {
        v.Update();
    }

    ::camera.Update();

    local mask;
    if (::battle.time_stop_count > 0) {
        ::battle.time_stop_count--;
        mask = ::battle.team[0].time_stop_mask & ::battle.team[1].time_stop_mask;
        ::battle.is_time_stop = true;
    } else if (::battle.team[0].time_stop_count > 0) {
        ::battle.team[0].time_stop_count--;
        mask = ::battle.team[0].time_stop_mask;
        ::battle.is_time_stop = true;
    } else if (::battle.team[1].time_stop_count > 0) {
        ::battle.team[1].time_stop_count--;
        mask = ::battle.team[1].time_stop_mask;
        ::battle.is_time_stop = true;
    } else if (::battle.slow_count) {
        ::battle.slow_count--;
        if (::battle.slow_count & 1) {
            mask = ::battle.team[0].time_stop_mask | ::battle.team[1].time_stop_mask;
            ::battle.is_time_stop = true;
        } else {
            mask = 65535;
            ::stage.Update();
            ::battle.is_time_stop = false;
        }
    } else {
        mask = 65535;
        ::stage.Update();
        ::battle.is_time_stop = false;
    }

    ::battle.group_player.SetUpdateMask(mask);
    ::effect.AddUpdateMask(mask);
    ::battle.group_player.Update();
    ::battle.group_effect.Update();
    ::battle.ContactTest();

    if (::battle.battleUpdate) {
        ::battle.battleUpdate();
    }

    ::battle.UpdateUser();
    ::battle.gauge.Update();

    foreach (v in ::battle.task) {
        v.Update();
    }

    ::battle.count++;
}
