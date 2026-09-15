#!/usr/bin/env bash
# 构建 Citrine 官网静态产物 → website/dist/
# 用法: bash website/build.sh
set -euo pipefail
cd "$(dirname "$0")/.."   # 仓库根

OUT=website/dist
mkdir -p "$OUT"

echo "[site] 拷贝示例页面与编译产物…"
for f in counter.html todo.html counter.js todo.js; do
  if [ -f "examples/$f" ]; then
    cp "examples/$f" "$OUT/"
  else
    # 源码存在而产物未编译时现场编译（bundler 环境用 bundle exec 解析 opal）
    base="${f%.js}"
    if [ -f "examples/$base.rb" ]; then
      (cd examples && bundle exec opal -c -I../lib -I. -o "../$OUT/$f" "$base.rb") \
        || (cd examples && opal -c -I../lib -I. -o "../$OUT/$f" "$base.rb")
    fi
  fi
done
cp examples/counter.html "$OUT/counter.html"
cp examples/todo.html "$OUT/todo.html"

echo "[site] 注入版本徽章（T5：来源 lib/citrine/version.rb，构建时替换）…"
VERSION=$(ruby -Ilib -e 'require "citrine/version"; print Citrine::VERSION')
TMP_WEBSITE=website/.website_build.rb
trap 'rm -f "$TMP_WEBSITE"' EXIT
ruby -e '
  src = File.read("website/website.rb")
  abort "website.rb 里找不到版本徽章 state（注入失败）" \
    unless src.sub!(/state :version, default: "v[0-9.]+"/,
                    %Q{state :version, default: "v#{ARGV[0]}"})
  File.write(ARGV[1], src)
' "$VERSION" "$TMP_WEBSITE"

echo "[site] 编译官网徽章组件…"
(cd website && (bundle exec opal -c -I../lib -I. -o dist/website.js .website_build.rb) \
  || (opal -c -I../lib -I. -o dist/website.js .website_build.rb))

echo "[site] 拷贝落地页…"
cp website/index.html "$OUT/"

echo "[site] 完成 → $OUT/"
ls "$OUT"
