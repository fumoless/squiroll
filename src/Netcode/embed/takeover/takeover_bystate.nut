// data/script/takeover.nut

data <- null;
active <- false;
MotionInitMap <- {
    [0]  = "Stand_Init",
    [40] = "DashFront_Init",    // 66 地面前冲
    [41] = "DashBack_Init",     // 44 地面后退
    [42] = "DashFront_Air_Init", // 空中66
    [43] = "DashBack_Air_Init",  // 空中44
    // ... 把你游戏中会出现的 motion ID 都填上
};

function SerializeActor(actor) {
    if (!actor) return null;
    local s = {};

    // 基础坐标与缩放
    try { s.x <- actor.x; } catch(e){}
    try { s.y <- actor.y; } catch(e){}
    try { s.sx <- actor.sx; } catch(e){}
    try { s.sy <- actor.sy; } catch(e){}
    try { s.direction <- actor.direction; } catch(e){} // 朝向
    try { s.alpha <- actor.alpha; } catch(e){}         // 透明度

    // 动画与动作
    try { s.motion <- actor.motion; } catch(e){}       // 动作ID
    try { s.take <- actor.keyTake; } catch(e){}        // 动作帧

    // 物理与速度
    try { s.vx <- actor.vx; } catch(e){} // X轴速度
    try { s.vy <- actor.vy; } catch(e){} // Y轴速度
    try { s.centerStop <- actor.centerStop; } catch(e){} // 回轴/离轴/滑行状态

    // 战斗交互状态
    try { s.hit_state <- actor.hit_state; } catch(e){} // 受击状态
    try { s.guard_state <- actor.guard_state; } catch(e){} // 防御状态
    try { s.hit_id <- actor.hit_id; } catch(e){} // 受击ID，可能是躺姿站姿？

    // 保存内部状态计时器与标志位
    try { s.count <- actor.count; } catch(e){}
    try { s.flag1 <- typeof actor.flag1 == "instance" ? null : actor.flag1; } catch(e){}
    try { s.flag2 <- typeof actor.flag2 == "instance" ? null : actor.flag2; } catch(e){}
    try { s.flag3 <- typeof actor.flag3 == "instance" ? null : actor.flag3; } catch(e){}
    try { s.flag4 <- typeof actor.flag4 == "instance" ? null : actor.flag4; } catch(e){}
    try { s.flag5 <- null;
        if (typeof actor.flag5 == "table") {
            // flag5 可能是 table（如空中dash），需要深拷贝并清理 instance 成员
            s.flag5 = {};
            foreach (k, v in actor.flag5) {
                if (typeof v != "instance" && typeof v != "function") {
                    s.flag5[k] <- v;
                }
            }
        } else if (typeof actor.flag5 != "instance") {
            s.flag5 = actor.flag5;
        }
    } catch(e){}

    if (actor.motion in MotionInitMap) {
        s.initFunc <- MotionInitMap[actor.motion];
    }

    return s;
}

function DeserializeActor(actor, data) {
    if (!actor || !data) return;

    if ("x" in data) actor.x = data.x;
    if ("y" in data) actor.y = data.y;
    if ("sx" in data) actor.sx = data.sx;
    if ("sy" in data) actor.sy = data.sy;
    if ("direction" in data) actor.direction = data.direction;
    if ("alpha" in data) actor.alpha = data.alpha;

    if ("vx" in data) actor.vx = data.vx;
    if ("vy" in data) actor.vy = data.vy;
    if ("centerStop" in data) actor.centerStop = data.centerStop;

    if ("hit_state" in data) actor.hit_state = data.hit_state;
    if ("guard_state" in data) actor.guard_state = data.guard_state;
    if ("hit_id" in data) actor.hit_id = data.hit_id;

    if ("count" in data) actor.count = data.count;
    if ("flag1" in data) actor.flag1 = data.flag1;
    if ("flag2" in data) actor.flag2 = data.flag2;
    if ("flag3" in data) actor.flag3 = data.flag3;
    if ("flag4" in data) actor.flag4 = data.flag4;
    if ("flag5" in data) actor.flag5 = data.flag5;


    if ("motion" in data) {
        ::print("Deserializing Actor Motion: " + data.motion + "\n");
        if ("initFunc" in data && data.initFunc) {
            if (data.initFunc == "DashFront_Init" || data.initFunc == "DashFront_Common") {
                local t = {
                    speed = data.flag1,
                    maxSpeed = data.flag2,
                    addSpeed = data.flag3,
                    wait = data.flag4
                };
                actor.DashFront_Common(t);
                actor.SetMotion(data.motion, data.take);
                actor.count = data.count;
            } else {
                // 重新调用 Init 函数，重建完整的 stateLabel/keyAction
                actor[data.initFunc](null);
                // Init 会把 motion 设为起始帧，所以要覆盖回保存时的帧
                actor.SetMotion(data.motion, data.take);
                // 恢复计数器
                actor.count = data.count;
            }
        } else {
            // 没有映射的动作，直接设 motion（兜底）
            if (actor.motion != data.motion) {
                actor.SetMotion(data.motion, data.take);
                actor.count = data.count;
            }
        }

        // if (actor.motion != 0) {
        //     actor.EndtoFreeMove();
        // }

    }
}

function AlignInput(team, target_frame, is_taking_over) {

    local function UpdateCommandDevice(actor, new_input) {
        if (actor && "command" in actor && actor.command) {

            // 更新squirrel层的引用
            // input_command.nut
            if ("device" in actor.command) {
                actor.command.device = new_input;
            }

            // 更新c++底层的绑定
            // input_command.nut中显示有一个.com 成员是::manbow.InputCommand()
            if ("com" in actor.command && actor.command.com) {
                // 让输入系统读到new_input
                actor.command.com.SetDevice(new_input);
            }

            ::print("Updated Command Device for Actor: " + (actor == team.master ? "Master" : "Slave") + "\n");
        }
    }

    // 手动控制
    if (is_taking_over) {
        // TODO: team.device_id应该是当前的物理设备ID
        // 如果是用键盘玩的team.device_id应该是-1，目前是强制改成键盘
        // 后续应该读入
        local my_device_id = -1; // 强制键盘
        // local my_device_id = team.device_id;
        team.input = ::input.CreatePlayerInputDevice(team.index, my_device_id);
        UpdateCommandDevice(team.master, team.input);
        if (team.slave) UpdateCommandDevice(team.slave, team.input);
        ::print("[Takeover] Player Control: LIVE INPUT (Device " + my_device_id + ") - Command Refreshed.\n");
        return;
    }


    // 正常录像回放
    if (::replay.recorder == null) return;

    local replay_slot_id = team.index;
    local replay_input = ::input.CreatePlayerInputDevice(team.index, team.device_id);
    // 相当于把键盘拔了，插上了录像的输入
    ::replay.recorder.SetDevice(replay_slot_id, replay_input);
    // 重置播放头，赋值给 team
    ::replay.recorder.BeginPlay(replay_slot_id);
    team.input = replay_input;
    UpdateCommandDevice(team.master, team.input);
    if (team.slave) {
        UpdateCommandDevice(team.slave, team.input);
    }

    ::print("[Takeover] Rewinding Replay Slot " + replay_slot_id + " to frame " + target_frame + "...\n");

    // 快进

    for (local i = 0; i < target_frame; i++) {
        team.input.Update();
        // if (i % 60 == 0 && team.index == 1) ::print("Frame " + i + " X=" + team.input.x + "\n");
    }
}

function Save() {
    ::rollback.save_rng();

    local snapshot = {
        frame = ::battle.count,
        teams = []
    };

    foreach (i, team in ::battle.team) {
        local t_data = {
            life = team.life,
            regain_life = team.regain_life,
            shield_life = team.shield_life,
            mp = team.mp,
            sp = team.sp,
            op = team.op,
            spell_active = team.spell_active,
            combo_count = team.combo_count,
            damage_scale = team.damage_scale,
            slave_ban = team.slave_ban,
            change_count = team.change_count,

            counter_scale = team.counter_scale, // 打康补正
            base_scale = team.base_scale, // 基础补正
            kaiki_scale = team.kaiki_scale, // 怪奇补正
            combo_damage = team.combo_damage, // 当前连段伤害
            combo_stun = team.combo_stun, // 连段眩晕值
            combo_wall = team.combo_wall, // 弹墙值
            combo_ground = team.combo_ground, // 弹地值

            mp_stop = team.mp_stop, // 灵力回复冷却
            sp_stop = team.sp_stop, // 大招槽回复冷却
            op_stop = team.op_stop, // 凭依槽回复冷却
            time_stop_count = team.time_stop_count, // 时停帧数（暗转）

            is_master_current = (team.current == team.master),

            master_state = SerializeActor(team.master),
            slave_state = SerializeActor(team.slave)

            device_id = team.device_id,
            index = team.index
        };
        snapshot.teams.append(t_data);
    }

    data = snapshot;
    ::print("[Takeover] Saved Frame: " + ::battle.count + "\n");
}

function Load() {
    if (data == null) {
        return;
    }
    ::collectgarbage();

    local clear_targets = ["projectiles", "atoms", "items"];
    foreach (list_name in clear_targets) {
        if (list_name in ::battle) {
            ::print("  Clearing " + list_name + "...\n");
            local list = ::battle[list_name];
            // 倒序遍历比较安全
            for (local i = list.len() - 1; i >= 0; i--) {
                try {
                    if ("Release" in list[i]) list[i].Release();
                } catch(e) {}
            }
            list.clear();
        }
    }

    // 重置玩家状态
    foreach (team in ::battle.team) {
        team.ResetRound();
    }

    ::rollback.load_rng(); // 恢复随机数
    if ("frame" in data) {
        ::battle.count = data.frame;
    }

    foreach (i, team in ::battle.team) {
        local t_data = data.teams[i];

        // team
        team.life = t_data.life;
        team.regain_life = t_data.regain_life;
        team.shield_life = t_data.shield_life;
        team.mp = t_data.mp;
        team.sp = t_data.sp;
        team.op = t_data.op;
        team.spell_active = t_data.spell_active;
        team.combo_count = t_data.combo_count;
        team.damage_scale = t_data.damage_scale;
        team.slave_ban = t_data.slave_ban;

        // combo
        if ("counter_scale" in t_data) team.counter_scale = t_data.counter_scale;
        if ("base_scale" in t_data) team.base_scale = t_data.base_scale;
        if ("kaiki_scale" in t_data) team.kaiki_scale = t_data.kaiki_scale;
        if ("combo_damage" in t_data) team.combo_damage = t_data.combo_damage;
        if ("combo_stun" in t_data) team.combo_stun = t_data.combo_stun;
        if ("combo_wall" in t_data) team.combo_wall = t_data.combo_wall;
        if ("combo_ground" in t_data) team.combo_ground = t_data.combo_ground;

        // stop
        if ("mp_stop" in t_data) team.mp_stop = t_data.mp_stop;
        if ("sp_stop" in t_data) team.sp_stop = t_data.sp_stop;
        if ("op_stop" in t_data) team.op_stop = t_data.op_stop;
        if ("time_stop_count" in t_data) team.time_stop_count = t_data.time_stop_count;

        // actor
        DeserializeActor(team.master, t_data.master_state);
        if (team.slave && t_data.slave_state) {
            DeserializeActor(team.slave, t_data.slave_state);
        }

        // 切换角色
        local target_actor = t_data.is_master_current ? team.master : team.slave;
        // 如果当前控制的角色不对，强制切过去
        if (target_actor != null && team.current != target_actor) {
            team.current = target_actor;

            // 通知相机关注新actor
            // 但好像游戏会自动调整
            if ("camera" in getroottable()) {
                try {
                    ::camera.RemoveTarget(team.master);
                    if (team.slave) ::camera.RemoveTarget(team.slave);
                    ::camera.AddTarget(team.current);
                } catch(e) {}
            }

            // 更新 team.target 的指向
            if (team.target && "team" in team.target) {
                team.target.team.target = team.current;
            }
        }

        // 输入流处理逻辑
        // 如果开启了takeover：
        // 1P切换为实时输入
        // 2P保持录像输入但必须倒带回save帧
        AlignInput(team, data.frame, i==0);
        if (team.master && "input" in team.master) {
            team.master.input = team.input;
        }
        if (team.slave && "input" in team.slave) {
            team.slave.input = team.input;
        }
        // if (i == 0) {
        //     // 玩家直接接管
        //     // 不需要倒带，直接换成新的手柄/键盘控制器
        //     team.input = ::input.CreatePlayerInputDevice(0, 0);
        //     ::print("[Takeover] P1 Swapped to Player Control\n");
        // }
        // else {
        //     // 对手继续按录像演，要倒带
        //     // 让录像读取头空转到 data.frame
        //     AlignInput(team, data.frame);
        // }

        // 强制剥夺ai控制权
        if ("type" in team) team.type = 0;
        if ("cpu" in team) team.cpu = false;
        if ("auto" in team) team.auto = false;
        if ("controller" in team) team.controller = null;

    }

    active = true;
    ::print("[Takeover] Loaded!\n");
}