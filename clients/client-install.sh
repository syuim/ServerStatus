#!/usr/bin/env bash
# ServerStatus 客户端一键接入（从 GitHub 下载）
# 用法: bash <(curl -sL https://raw.githubusercontent.com/syuim/ServerStatus/master/clients/client-install.sh)
# 可用环境变量覆盖: SERVER / PORT / SS_USER / KEY / TAGS / NAME / TRAFFIC_RESET_DAY / TRAFFIC_QUOTA
set -euo pipefail

SERVER="${SERVER:-rn.127315.xyz}"
PORT="${PORT:-35601}"
# 注意: 不能叫 USER，会与 shell 内置 $USER 冲突
SS_USER="${SS_USER:-suyu}"
KEY="${KEY:-68f30717b2bf0a5d33ed7a53c8f40bff}"
NAME="${NAME:-}"
TAGS="${TAGS:-}"
TRAFFIC_RESET_DAY="${TRAFFIC_RESET_DAY:-1}"
TRAFFIC_QUOTA="${TRAFFIC_QUOTA:-0}"
REPO="syuim/ServerStatus"
BRANCH="master"
RAW="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
MIRROR="https://cdn.jsdelivr.net/gh/${REPO}@${BRANCH}"
DIR="/usr/local/ServerStatus/client"

fetch() { # fetch <url> <输出文件>
  if curl -sSL --fail --connect-timeout 8 -o "$2" "$1"; then return 0; fi
  curl -sSL --fail --connect-timeout 8 -o "$2" "${1/$RAW/$MIRROR}" 2>/dev/null && return 0
  wget -q --no-check-certificate --timeout=8 -O "$2" "${1/$RAW/$MIRROR}"
}

[[ $EUID -ne 0 ]] && echo "请用 root 运行" && exit 1

if command -v python3 >/dev/null 2>&1; then
  PYTHON=python3
elif command -v python >/dev/null 2>&1; then
  PYTHON=python
else
  echo ">> 安装 python3 ..."
  (apt-get update -qq && apt-get install -y python3) || yum install -y python3
  PYTHON=python3
fi

echo ">> 安装 vnstat（总流量统计，跨重启准确）..."
if ! command -v vnstat >/dev/null 2>&1; then
  (apt-get update -qq && apt-get install -y vnstat) || yum install -y vnstat
fi
systemctl enable --now vnstat >/dev/null 2>&1 || true

echo ">> 下载客户端 ..."
mkdir -p "$DIR"
fetch "$RAW/clients/status-client.py" "$DIR/status-client.py"
fetch "$RAW/service/status-client.service" /etc/systemd/system/status-client.service

echo ">> 写入配置 ..."
sed -i "s|^SERVER = .*|SERVER = \"${SERVER}\"|" "$DIR/status-client.py"
sed -i "s|^PORT = .*|PORT = ${PORT}|" "$DIR/status-client.py"
sed -i "s|^USER = .*|USER = \"${SS_USER}\"|" "$DIR/status-client.py"
sed -i "s|^PASSWORD = .*|PASSWORD = \"${KEY}\"|" "$DIR/status-client.py"
sed -i "s|^TRAFFIC_RESET_DAY = .*|TRAFFIC_RESET_DAY = ${TRAFFIC_RESET_DAY}|" "$DIR/status-client.py"

# 周期流量配额: 支持纯数字(字节)或 500M / 2G / 1T 格式
QUOTA_BYTES="$TRAFFIC_QUOTA"
case "$TRAFFIC_QUOTA" in
  *[kK]) QUOTA_BYTES=$(( ${TRAFFIC_QUOTA%[kK]} * 1024 )) ;;
  *[mM]) QUOTA_BYTES=$(( ${TRAFFIC_QUOTA%[mM]} * 1024 * 1024 )) ;;
  *[gG]) QUOTA_BYTES=$(( ${TRAFFIC_QUOTA%[gG]} * 1024 * 1024 * 1024 )) ;;
  *[tT]) QUOTA_BYTES=$(( ${TRAFFIC_QUOTA%[tT]} * 1024 * 1024 * 1024 * 1024 )) ;;
esac
sed -i "s|^TRAFFIC_QUOTA = .*|TRAFFIC_QUOTA = ${QUOTA_BYTES}|" "$DIR/status-client.py"

if [[ -n "$TAGS" ]]; then
  # TAGS 格式: 文本:颜色,文本  例如 "RN:blue,9929,CMIN2"
  TAGS_PY="["
  first=1
  IFS=',' read -ra items <<< "$TAGS"
  for item in "${items[@]}"; do
    text="${item%%:*}"
    color="${item##*:}"
    [[ "$text" == "$color" ]] && color=""
    [[ $first -eq 0 ]] && TAGS_PY+=", "
    first=0
    if [[ -n "$color" ]]; then
      TAGS_PY+="{\"text\": \"${text}\", \"color\": \"${color}\"}"
    else
      TAGS_PY+="{\"text\": \"${text}\"}"
    fi
  done
  TAGS_PY+="]"
  $PYTHON - "$DIR/status-client.py" "$TAGS_PY" <<'PYEOF'
import re
import sys
path, tags = sys.argv[1], sys.argv[2]
src = open(path, encoding='utf-8').read()
src = re.sub(r'TAGS = \[.*?\]', 'TAGS = ' + tags, src, count=1, flags=re.S)
open(path, 'w', encoding='utf-8').write(src)
PYEOF
fi

echo ">> 配置服务端节点 ..."
SERVER_CONFIG="/usr/local/ServerStatus/server/config.json"
if [[ -f "$SERVER_CONFIG" ]]; then
  $PYTHON - "$SERVER_CONFIG" "$SS_USER" "$KEY" "$NAME" <<'PYEOF'
import json
import socket
import sys
path, user, key, name = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
with open(path) as f:
    cfg = json.load(f)
servers = cfg.setdefault('servers', [])
for s in servers:
    if s.get('username') == user:
        s['password'] = key
        if name:
            s['name'] = name
        print("   节点 %s 已存在，密钥已更新%s" % (user, '，节点名替换为 %s' % name if name else ''))
        break
else:
    servers.append({
        'username': user, 'password': key, 'name': name or socket.gethostname(),
        'type': 'KVM', 'host': '', 'location': '', 'disabled': False, 'region': ''
    })
    print("   节点 %s 不存在，已添加 (name=%s)" % (user, name or socket.gethostname()))
with open(path, 'w') as f:
    json.dump(cfg, f, indent=1)
PYEOF
  systemctl restart sergate 2>/dev/null || true
else
  echo "   未检测到本机服务端，跳过"
fi

echo ">> 安装 systemd 服务 ..."
systemctl daemon-reload
systemctl enable status-client >/dev/null 2>&1
systemctl restart status-client

sleep 3
if systemctl is-active --quiet status-client; then
  echo "✓ 接入成功: ${SS_USER}@${SERVER}:${PORT} (节点名: ${NAME:-$(hostname)})"
  echo "  日志: journalctl -u status-client -f"
else
  echo "✗ 启动失败，查看日志: journalctl -u status-client --no-pager -n 30"
  exit 1
fi
