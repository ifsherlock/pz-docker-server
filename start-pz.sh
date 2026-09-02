#!/bin/bash
# 位于 /home/steam/start-pz.sh

PZ_INSTALL_DIR="/opt/pzserver"
STEAMCMD_DIR="/home/steam/steamcmd"

echo "--- Supervisor 正在启动僵毁服务端 ---"
# 确认分支
# 如果 PZ_BRANCH 为空，默认为 public
BRANCH=${PZ_BRANCH:-public}
# 面板可持久化选择 Steam 分支；优先级高于容器环境变量，避免重建后丢失选择。
PANEL_SETTINGS_FILE="/opt/pz-web-backend/panel_settings.json"
if [ -f "$PANEL_SETTINGS_FILE" ] && command -v python3 >/dev/null 2>&1; then
    PANEL_BRANCH="$(python3 -c "import json;print(json.load(open('$PANEL_SETTINGS_FILE')).get('game_branch') or '')" 2>/dev/null || true)"
    if [ -n "$PANEL_BRANCH" ] && [[ "$PANEL_BRANCH" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,31}$ ]]; then
        BRANCH="$PANEL_BRANCH"
    fi
fi

# 管理员账户/密码由面板保存到 panel_settings.json。
# 游戏账户实际保存在 whitelist 数据库；密码交给游戏自身的 -adminpassword 逻辑处理。
ADMIN_USERNAME="admin"
ADMIN_PASSWORD="admin"
PANEL_ADMIN_USERNAME=""
PANEL_ADMIN_PASSWORD=""
if [ -f "$PANEL_SETTINGS_FILE" ] && command -v python3 >/dev/null 2>&1; then
    PANEL_ADMIN_USERNAME="$(python3 -c "import json;print(json.load(open('$PANEL_SETTINGS_FILE')).get('admin_username') or '')" 2>/dev/null || true)"
    PANEL_ADMIN_PASSWORD="$(python3 -c "import json;print(json.load(open('$PANEL_SETTINGS_FILE')).get('admin_password') or '')" 2>/dev/null || true)"
fi
if [ -n "$PANEL_ADMIN_USERNAME" ] && [[ "$PANEL_ADMIN_USERNAME" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,31}$ ]]; then
    ADMIN_USERNAME="$PANEL_ADMIN_USERNAME"
fi
if [ -n "$PANEL_ADMIN_PASSWORD" ] && [[ "$PANEL_ADMIN_PASSWORD" != *$'\n'* ]] && [[ "$PANEL_ADMIN_PASSWORD" != *$'\r'* ]]; then
    ADMIN_PASSWORD="$PANEL_ADMIN_PASSWORD"
fi

ADMIN_DB="$PZ_DATA_DIR/db/servertest.db"
if [ -f "$ADMIN_DB" ] && [ -n "$PANEL_ADMIN_USERNAME" ]; then
    ADMIN_DB="$ADMIN_DB" ADMIN_USERNAME="$ADMIN_USERNAME" python3 - <<'PY'
import os
import sqlite3

db_path = os.environ["ADMIN_DB"]
username = os.environ["ADMIN_USERNAME"]
db = sqlite3.connect(db_path)
try:
    row = db.execute("SELECT id FROM whitelist WHERE role = 7 ORDER BY id LIMIT 1").fetchone()
    if row:
        db.execute("UPDATE whitelist SET username = ? WHERE id = ?", (username, row[0]))
    else:
        print("no existing administrator record; the game will initialize it")
    db.commit()
finally:
    db.close()
PY
    echo "--- [Game] 管理员账户已同步: $ADMIN_USERNAME ---"
fi
BETA_ARGS=""

if [ "$BRANCH" = "public" ] || [ "$BRANCH" = "latest" ]; then
    echo "--- [Game] 目标分支: 稳定版 (public) ---"
    # SteamCMD 会在持久化 Steam 目录中记住上一次选择的 beta。
    # 即使这里省略 -beta，也可能继续沿用旧的 42.19 分支，因此显式切回 public。
    BETA_ARGS="-beta public"
else
    echo "--- [Game] 目标分支: 测试版 ($BRANCH) ---"
    BETA_ARGS="-beta $BRANCH"
fi

# 处理国内源
STEAM_CLIENT_ARGS=""

# 检查环境变量 STEAMCMD_CN_MIRROR_ID 是否存在且不为空
if [ -n "$STEAMCMD_CN_MIRROR_ID" ]; then
    echo "--- [Game] ⚡ 检测到国内源配置，强制指定下载节点 ID: $STEAMCMD_CN_MIRROR_ID ---"
    # 将 -cellid 参数拼接到启动参数中
    STEAM_CLIENT_ARGS="$STEAM_CLIENT_ARGS -cellid $STEAMCMD_CN_MIRROR_ID"
fi
echo "--- [Game] 开始检查更新... ---"
echo "--- [Game] SteamCMD 参数: $STEAM_CLIENT_ARGS"

# timeout 600s: 给 SteamCMD 10分钟时间。如果超时或失败，尝试继续启动旧版本。
timeout 600s $STEAMCMD_DIR/steamcmd.sh $STEAM_CLIENT_ARGS \
    +force_install_dir $PZ_INSTALL_DIR \
    +login anonymous \
    +app_update 380870 $BETA_ARGS validate \
    +quit || echo "--- [Game] ⚠️ 更新过程遇到错误或超时，尝试直接启动服务器... ---"

# --- 启动服务器 ---
cd $PZ_INSTALL_DIR
if [ ! -f "./start-server.sh" ]; then
    echo "错误: 找不到 start-server.sh，可能是游戏下载完全失败。"
    exit 1
fi

# --- 限制 JVM 内存 ---
# 游戏默认 -Xmx8g，对少人/本地 NAS 服务端过高。
# 注意：每次 steamcmd validate 会把这个 json 还原成默认 8g，
# 所以必须在这里(validate 之后、启动游戏之前)重新应用。
# 内存值优先级：
#   1. 面板设置文件 panel_settings.json 的 memory_limit (前端可改，无需重建镜像)
#   2. 环境变量 PZ_MEMORY_LIMIT
#   3. 默认 3g
# Build 42 服务端不建议 < 2g。
PZ_MEMORY_LIMIT="${PZ_MEMORY_LIMIT:-3g}"
# 面板设置文件路径 (挂载卷 data/web-backend -> /opt/pz-web-backend)
PANEL_SETTINGS_FILE="/opt/pz-web-backend/panel_settings.json"
if [ -f "$PANEL_SETTINGS_FILE" ]; then
    SETTINGS_MEM="$(python3 -c "import json;print(json.load(open('$PANEL_SETTINGS_FILE')).get('memory_limit') or '')" 2>/dev/null)"
    if [ -n "$SETTINGS_MEM" ]; then
        PZ_MEMORY_LIMIT="$SETTINGS_MEM"
        echo "--- [Game] 从面板设置读取内存上限: -Xmx${PZ_MEMORY_LIMIT} ---"
    fi
fi
if [[ ! "$PZ_MEMORY_LIMIT" =~ ^[1-9][0-9]*[mMgG]$ ]]; then
    echo "--- [Game] 无效的 JVM 内存上限 '$PZ_MEMORY_LIMIT'，回退为 3g ---"
    PZ_MEMORY_LIMIT="3g"
fi
if [ -f "./ProjectZomboid64.json" ]; then
    sed -i "s/-Xmx[0-9]*[mMgG]/-Xmx${PZ_MEMORY_LIMIT}/" ./ProjectZomboid64.json
    echo "--- [Game] JVM 内存上限已设为 -Xmx${PZ_MEMORY_LIMIT} ---"
fi

# 使用 exec 替换当前 shell 进程
# 这样 supervisord 的停止信号 (SIGTERM) 能直接传给 java 进程
# 保证游戏能有机会执行“保存并退出”逻辑
exec ./start-server.sh -adminpassword "$ADMIN_PASSWORD" -cachedir=/home/steam/Zomboid
