#!/usr/bin/env bash
# 构建 Citrine 官网静态产物 → website/dist/
# 用法: bin/citrine build-site  （或 bash website/build.sh）
set -euo pipefail
cd "$(dirname "$0")/.."   # 仓库根

OUT=website/dist
mkdir -p "$OUT"

echo "[site] 拷贝示例页面与编译产物…"
for f in counter.html todo.html counter.js todo.js; do
  if [ -f "examples/$f" ]; then
    cp "examples/$f" "$OUT/"
  else
    # 源码存在而产物未编译时现场编译（与手工命令同形态）
    base="${f%.js}"
    [ -f "examples/$base.rb" ] && (cd examples && opal -c -I../lib -I. -o "../$OUT/$f" "$base.rb")
  fi
done
cp examples/counter.html "$OUT/counter.html"
cp examples/todo.html "$OUT/todo.html"

echo "[site] 编译官网徽章组件…"
(cd website && opal -c -I../lib -I. -o dist/website.js website.rb)

echo "[site] 拷贝落地页…"
cp website/index.html "$OUT/"

echo "[site] 完成 → $OUT/"
ls "$OUT"
