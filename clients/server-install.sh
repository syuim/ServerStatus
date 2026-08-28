#!/usr/bin/env bash
# ServerStatus 服务端安装/更新（下载 GitHub Actions 自动编译的二进制 + 更新前端，存在则替换）
# 用法: bash <(curl -sL https://raw.githubusercontent.com/syuim/ServerStatus/master/clients/server-install.sh)
# 可用环境变量覆盖: SERVER_PORT / WEB_DIR / CONFIG_DIR
set -euo pipefail

SERVER_PORT="${SERVER_PORT:-35601}"
WEB_DIR="${WEB_DIR:-/usr/local/ServerStatus/web}"
DIR="${CONFIG_DIR:-/usr/local/ServerStatus/server}"
REPO="syuim/ServerStatus"
BRANCH="master"
RAW="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
RELEASE_URL="https://github.com/${REPO}/releases/latest/download"

[[ $EUID -ne 0 ]] && echo "请用 root 运行" && exit 1

case "$(uname -m)" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) echo "✗ 不支持的架构: $(uname -m)"; exit 1 ;;
esac

echo ">> 下载 sergate (linux-${ARCH}) ..."
mkdir -p "$DIR"
TMP_BIN="$DIR/sergate.new"
if ! curl -sSL --fail --connect-timeout 10 -o "$TMP_BIN" "$RELEASE_URL/sergate-linux-${ARCH}"; then
  echo "✗ 下载失败: $RELEASE_URL/sergate-linux-${ARCH}"
  echo "  请确认 GitHub Actions 已完成自动编译并发布 release"
  rm -f "$TMP_BIN"
  exit 1
fi
chmod +x "$TMP_BIN"

echo ">> 安装/替换二进制 ..."
if [[ -f "$DIR/sergate" ]]; then
  systemctl stop sergate 2>/dev/null || true
  [[ ! -f "$DIR/sergate.bak" ]] && cp "$DIR/sergate" "$DIR/sergate.bak"
  mv "$TMP_BIN" "$DIR/sergate"
  echo "   已存在，已替换（首次替换已备份为 sergate.bak）"
else
  mv "$TMP_BIN" "$DIR/sergate"
  echo "   不存在，已安装"
fi

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
if ! curl -sSL --fail --connect-timeout 8 -o /etc/systemd/system/sergate.service "$RAW/service/sergate.service"; then
  wget -q --no-check-certificate --timeout=8 -O /etc/systemd/system/sergate.service "$RAW/service/sergate.service"
fi
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
