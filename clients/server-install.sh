#!/usr/bin/env bash
# ServerStatus 服务端安装/更新（从 GitHub 下载源码编译 + 更新前端，存在则替换）
# 用法: bash <(curl -sL https://raw.githubusercontent.com/syuim/ServerStatus/master/clients/server-install.sh)
# 可用环境变量覆盖: SERVER_PORT / WEB_DIR / CONFIG_DIR
set -euo pipefail

SERVER_PORT="${SERVER_PORT:-35601}"
WEB_DIR="${WEB_DIR:-/usr/local/ServerStatus/web}"
DIR="${CONFIG_DIR:-/usr/local/ServerStatus/server}"
BUILD="/tmp/sergate-build"
REPO="syuim/ServerStatus"
BRANCH="master"
RAW="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
MIRROR="https://cdn.jsdelivr.net/gh/${REPO}@${BRANCH}"

# server 源码文件（相对仓库根）
SRC_FILES=(
  "server/Makefile"
  "server/include/detect.h"
  "server/include/system.h"
  "server/include/argparse.h"
  "server/include/json.h"
  "server/src/argparse.c"
  "server/src/json.c"
  "server/src/system.c"
  "server/src/main.cpp"
  "server/src/main.h"
  "server/src/netban.cpp"
  "server/src/netban.h"
  "server/src/network_client.cpp"
  "server/src/network.cpp"
  "server/src/network.h"
  "server/src/server.cpp"
  "server/src/server.h"
)

fetch() { # fetch <url> <输出文件>
  if curl -sSL --fail --connect-timeout 8 -o "$2" "$1"; then return 0; fi
  curl -sSL --fail --connect-timeout 8 -o "$2" "${1/$RAW/$MIRROR}" 2>/dev/null && return 0
  wget -q --no-check-certificate --timeout=8 -O "$2" "${1/$RAW/$MIRROR}"
}

[[ $EUID -ne 0 ]] && echo "请用 root 运行" && exit 1

if ! command -v g++ >/dev/null 2>&1 || ! command -v make >/dev/null 2>&1; then
  echo ">> 安装编译环境 (g++/make) ..."
  (apt-get update -qq && apt-get install -y g++ make) || yum install -y gcc-c++ make
fi

echo ">> 下载源码 ..."
rm -rf "$BUILD"
mkdir -p "$BUILD/include" "$BUILD/src" "$BUILD/obj"
for f in "${SRC_FILES[@]}"; do
  out="$BUILD/${f#server/}"
  fetch "$RAW/$f" "$out"
done

echo ">> 编译 sergate ..."
make -C "$BUILD" -j"$(nproc 2>/dev/null || echo 2)" >/dev/null
[[ -f "$BUILD/sergate" ]] || { echo "✗ 编译失败"; exit 1; }

echo ">> 安装/替换二进制 ..."
mkdir -p "$DIR"
if [[ -f "$DIR/sergate" ]]; then
  systemctl stop sergate 2>/dev/null || true
  [[ ! -f "$DIR/sergate.bak" ]] && cp "$DIR/sergate" "$DIR/sergate.bak"
  cp "$BUILD/sergate" "$DIR/sergate"
  echo "   已存在，已替换（首次替换已备份为 sergate.bak）"
else
  cp "$BUILD/sergate" "$DIR/sergate"
  echo "   不存在，已安装"
fi
chmod +x "$DIR/sergate"

if [[ ! -f "$DIR/config.json" ]]; then
  KEY="${KEY:-$(openssl rand -hex 16 2>/dev/null || (cat /dev/urandom | tr -dc 'a-f0-9' | head -c 32))}"
  cat > "$DIR/config.json" <<EOF
{
 "key": "$KEY",
 "servers": []
}
EOF
  echo "   已生成 config.json（全局密钥: $KEY，安装客户端时用 KEY=$KEY）"
fi

echo ">> 更新前端 (web/dist) ..."
WEB_TMP="/tmp/serverstatus-web"
rm -rf "$WEB_TMP"
mkdir -p "$WEB_TMP"
TARBALL="https://codeload.github.com/${REPO}/tar.gz/refs/heads/${BRANCH}"
if ! curl -sSL --fail --connect-timeout 10 -o "$WEB_TMP/repo.tar.gz" "$TARBALL"; then
  wget -q --no-check-certificate --timeout=15 -O "$WEB_TMP/repo.tar.gz" "$TARBALL"
fi
tar -xzf "$WEB_TMP/repo.tar.gz" -C "$WEB_TMP"
WEB_SRC="$WEB_TMP/ServerStatus-${BRANCH}/web/dist"
if [[ -d "$WEB_SRC" ]]; then
  mkdir -p "$WEB_DIR"
  cp -r "$WEB_SRC"/. "$WEB_DIR/"
  find "$WEB_DIR" -name '._*' -delete
  chown -R root:root "$WEB_DIR"
  for f in "$WEB_DIR"/js/*.js "$WEB_DIR"/css/*.css; do
    [[ -f "$f" ]] || continue
    base=$(basename "$f")
    if ! grep -q "$base" "$WEB_DIR/index.html"; then
      rm -f "$f"
    fi
  done
  echo "   前端已更新（web: ${WEB_DIR}）"
else
  echo "   警告: 未找到 web/dist，跳过前端更新"
fi

echo ">> 安装 systemd 服务 ..."
fetch "$RAW/service/sergate.service" /etc/systemd/system/sergate.service
systemctl daemon-reload
systemctl enable sergate >/dev/null 2>&1
systemctl restart sergate

sleep 3
if systemctl is-active --quiet sergate; then
  echo "✓ 服务端运行中: 端口 ${SERVER_PORT} (web: ${WEB_DIR})"
  echo "  日志: journalctl -u sergate -f"
else
  echo "✗ 启动失败，查看日志: journalctl -u sergate --no-pager -n 30"
  exit 1
fi
