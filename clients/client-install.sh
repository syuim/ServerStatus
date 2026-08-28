#!/usr/bin/env bash
# ServerStatus 客户端一键接入（从 GitHub 下载）
# 用法: bash <(curl -sL https://raw.githubusercontent.com/syuim/ServerStatus/master/clients/client-install.sh)
# 可用参数: --server <地址> --port <端口> --key <密钥> --name <显示名>
#           --tags <标签> --reset-day <每月几号> --quota <配额，如 1T>
# 只需提供 --key（服务端 config.json 顶层 key）；user 由客户端自动生成，无需关心
# 也可用环境变量覆盖: SERVER / PORT / KEY / TAGS / NAME / TRAFFIC_RESET_DAY / TRAFFIC_QUOTA / CLIENT_DIR
set -euo pipefail

SERVER="${SERVER:-rn.127315.xyz}"
PORT="${PORT:-35601}"
KEY="${KEY:-}"
NAME="${NAME:-}"
TAGS="${TAGS:-}"
TRAFFIC_RESET_DAY="${TRAFFIC_RESET_DAY:-1}"
TRAFFIC_QUOTA="${TRAFFIC_QUOTA:-0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --server) SERVER="${2:-}"; shift 2 ;;
    --port) PORT="${2:-}"; shift 2 ;;
    --key) KEY="${2:-}"; shift 2 ;;
    --name) NAME="${2:-}"; shift 2 ;;
    --tags) TAGS="${2:-}"; shift 2 ;;
    --reset-day) TRAFFIC_RESET_DAY="${2:-}"; shift 2 ;;
    --quota) TRAFFIC_QUOTA="${2:-}"; shift 2 ;;
    *) echo "✗ 未知参数: $1"; exit 1 ;;
  esac
done
REPO="syuim/ServerStatus"
BRANCH="master"
RAW="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
DIR="${CLIENT_DIR:-/usr/local/ServerStatus/client}"
SERVER_CONFIG="/usr/local/ServerStatus/server/config.json"

fetch() { # fetch <url> <输出文件>
  curl -sSL --fail --connect-timeout 8 -o "$2" "$1"
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
# 按实际安装目录修正 service 文件（支持 CLIENT_DIR 覆盖）
sed -i "s|/usr/local/ServerStatus/client|$DIR|g" /etc/systemd/system/status-client.service

echo ">> 写入配置 ..."
# 密钥不内置在仓库：优先取环境变量 KEY，否则读本机服务端 config.json 的全局 key
if [[ -z "$KEY" ]]; then
  if [[ -f "$SERVER_CONFIG" ]]; then
    KEY=$($PYTHON -c "import json;print(json.load(open('$SERVER_CONFIG')).get('key') or '')" 2>/dev/null || true)
  fi
  if [[ -z "$KEY" ]]; then
    echo "✗ 未提供 KEY：请通过 KEY=<服务端config.json顶层key> 传入（或本机已有服务端时自动读取）"
    exit 1
  fi
fi
sed -i "s|^SERVER = .*|SERVER = \"${SERVER}\"|" "$DIR/status-client.py"
sed -i "s|^PORT = .*|PORT = ${PORT}|" "$DIR/status-client.py"
sed -i "s|^PASSWORD = .*|PASSWORD = \"${KEY}\"|" "$DIR/status-client.py"
sed -i "s|^NODE_NAME = .*|NODE_NAME = \"${NAME}\"|" "$DIR/status-client.py"
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

echo ">> 安装 systemd 服务 ..."
systemctl daemon-reload
systemctl enable status-client >/dev/null 2>&1
systemctl restart status-client

sleep 3
if systemctl is-active --quiet status-client; then
  echo "✓ 接入成功: ${SERVER}:${PORT} (显示名: ${NAME:-$(hostname)})"
  echo "  日志: journalctl -u status-client -f"
else
  echo "✗ 启动失败，查看日志: journalctl -u status-client --no-pager -n 30"
  exit 1
fi
