#!/bin/bash
# 用法: ./push.sh <GitHub用户名> [仓库名]
set -euo pipefail
USER_NAME="${1:?用法: ./push.sh <GitHub用户名> [仓库名]}"
REPO="${2:-rivals-hub}"

sed -i "s/^local GITHUB_USER = \"YOUR_NAME\"/local GITHUB_USER = \"$USER_NAME\"/" loader.lua
grep -q "GITHUB_USER = \"$USER_NAME\"" loader.lua || { echo "替换用户名失败"; exit 1; }

git add -A
git -c user.name="${GIT_NAME:-$USER_NAME}" -c user.email="${GIT_EMAIL:-$USER_NAME@users.noreply.github.com}" \
    commit -m "rivals hub: loader + main" >/dev/null 2>&1 || echo "(无改动可提交)"

git remote remove origin 2>/dev/null || true
git remote add origin "https://github.com/$USER_NAME/$REPO.git"
git branch -M main
git push -u origin main

echo
echo "推送完成。游戏里用这一行："
echo "loadstring(game:HttpGet(\"https://raw.githubusercontent.com/$USER_NAME/$REPO/main/loader.lua\"))()"
