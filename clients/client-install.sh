#!/usr/bin/env bash
# ServerStatus 客户端一键接入（从 GitHub 下载）
# 用法: bash <(curl -sL https://raw.githubusercontent.com/syuim/ServerStatus/master/clients/client-install.sh)
# 可用环境变量覆盖: SERVER / PORT / USER / KEY / TAGS
set -euo pipefail

SERVER="${SERVER:-rn.127315.xyz}"
PORT="${PORT:-35601}"
USER="${USER:-suyu}"
KEY="${KEY:-68f30717b2bf0a5d33ed7a53c8f40bff}"
NAME="${NAME:-$(hostname)}"
TAGS="${TAGS:-}"
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

echo ">> 下载客户端 ..."
mkdir -p "$DIR"
fetch "$RAW/clients/status-client.py" "$DIR/status-client.py"
fetch "$RAW/service/status-client.service" /etc/systemd/system/status-client.service

echo ">> 写入配置 ..."
sed -i "s|^SERVER = .*|SERVER = \"${SERVER}\"|" "$DIR/status-client.py"
sed -i "s|^PORT = .*|PORT = ${PORT}|" "$DIR/status-client.py"
sed -i "s|^USER = .*|USER = \"${USER}\"|" "$DIR/status-client.py"
sed -i "s|^PASSWORD = .*|PASSWORD = \"${KEY}\"|" "$DIR/status-client.py"

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

echo ">> 安装 systemd 服务 ..."
systemctl daemon-reload
systemctl enable status-client >/dev/null 2>&1
systemctl restart status-client

sleep 3
if systemctl is-active --quiet status-client; then
  echo "✓ 接入成功: ${USER}@${SERVER}:${PORT} (节点名: ${NAME})"
  echo "  日志: journalctl -u status-client -f"
else
  echo "✗ 启动失败，查看日志: journalctl -u status-client --no-pager -n 30"
  exit 1
fi
