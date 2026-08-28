#!/usr/bin/env bash
# ServerStatus 前端部署/更新（从 GitHub 下载构建产物，存在则替换）
# 用法: bash <(curl -sL https://raw.githubusercontent.com/syuim/ServerStatus/master/clients/web-install.sh)
# 可用环境变量覆盖: WEB_DIR
set -euo pipefail

WEB_DIR="${WEB_DIR:-/usr/local/ServerStatus/web}"
TMP="/tmp/serverstatus-web"
REPO="syuim/ServerStatus"
BRANCH="master"
TARBALL="https://codeload.github.com/${REPO}/tar.gz/refs/heads/${BRANCH}"

[[ $EUID -ne 0 ]] && echo "请用 root 运行" && exit 1

echo ">> 下载仓库产物 ..."
rm -rf "$TMP"
mkdir -p "$TMP"
if ! curl -sSL --fail --connect-timeout 10 -o "$TMP/repo.tar.gz" "$TARBALL"; then
  wget -q --no-check-certificate --timeout=15 -O "$TMP/repo.tar.gz" "$TARBALL"
fi

tar -xzf "$TMP/repo.tar.gz" -C "$TMP"
SRC="$TMP/ServerStatus-${BRANCH}/web/dist"
[[ -d "$SRC" ]] || { echo "✗ 解压失败，未找到 web/dist"; exit 1; }

echo ">> 替换前端文件 ..."
mkdir -p "$WEB_DIR"
cp -r "$SRC"/. "$WEB_DIR/"
find "$WEB_DIR" -name '._*' -delete
chown -R root:root "$WEB_DIR"

echo ">> 清理旧版静态资源 ..."
for f in "$WEB_DIR"/js/*.js "$WEB_DIR"/css/*.css; do
  [[ -f "$f" ]] || continue
  base=$(basename "$f")
  if ! grep -q "$base" "$WEB_DIR/index.html"; then
    rm -f "$f"
  fi
done

echo "✓ 前端已更新（web: ${WEB_DIR}）"
