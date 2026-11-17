#!/bin/bash
# 用法:
#   ./push.sh <GitHub用户名> <token> [仓库名]
#   TOKEN=ghp_xxx ./push.sh <GitHub用户名>
# 会自动建仓库（已存在则跳过）→ 推送 → 打印 raw 地址
set -euo pipefail

USER_NAME="${1:?用法: ./push.sh <GitHub用户名> <token> [仓库名]}"
TOKEN="${2:-${TOKEN:-}}"
REPO="${3:-rivals-hub}"

if [ -z "$TOKEN" ]; then
    echo "缺少 token：./push.sh <用户名> ghp_xxxx"; exit 1
fi

echo "== 1/3 检查/创建仓库 $USER_NAME/$REPO =="
code=$(curl -s -o /tmp/gh_repo.json -w '%{http_code}' \
    -H "Authorization: token $TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$USER_NAME/$REPO")
if [ "$code" = "404" ]; then
    code=$(curl -s -o /tmp/gh_repo.json -w '%{http_code}' -X POST \
        -H "Authorization: token $TOKEN" \
        -H "Accept: application/vnd.github+json" \
        https://api.github.com/user/repos \
        -d "{\"name\":\"$REPO\",\"description\":\"Rivals hub\",\"private\":false,\"auto_init\":false}")
    echo "   已创建 (HTTP $code)"
else
    echo "   已存在 (HTTP $code)"
fi
if [ "$code" != "201" ] && [ "$code" != "200" ]; then
    echo "   创建失败:"; head -c 400 /tmp/gh_repo.json; echo; exit 1
fi

echo "== 2/3 替换 loader 里的用户名 =="
sed -i "s/^local GITHUB_USER = \"[^\"]*\"/local GITHUB_USER = \"$USER_NAME\"/" loader.lua
grep -n "^local GITHUB_USER" loader.lua

echo "== 3/3 推送 =="
git add -A
git -c user.name="${GIT_NAME:-$USER_NAME}" -c user.email="${GIT_EMAIL:-$USER_NAME@users.noreply.github.com}" \
    commit -m "rivals hub: loader + main" >/dev/null 2>&1 || echo "   (无新改动)"
git remote remove origin 2>/dev/null || true
git remote add origin "https://$TOKEN@github.com/$USER_NAME/$REPO.git"
git branch -M main
git push -u origin main
git remote set-url origin "https://github.com/$USER_NAME/$REPO.git"   # 推完把 token 从 remote 里摘掉

echo
echo "=========================================="
echo "完成。游戏里用这一行："
echo "loadstring(game:HttpGet(\"https://raw.githubusercontent.com/$USER_NAME/$REPO/main/loader.lua\"))()"
echo "直连正文："
echo "loadstring(game:HttpGet(\"https://raw.githubusercontent.com/$USER_NAME/$REPO/main/main.lua\"))()"
echo "=========================================="
echo "现在去 https://github.com/settings/tokens 把这个 token 删掉"
