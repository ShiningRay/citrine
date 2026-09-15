# frozen_string_literal: true

# M1-5：prod_check 红线守门——Rakefile 产物禁用字符串清单（needles）必须与
# lib/citrine/debug*.rb 的探针面严格同步（DESIGN-devtools 第六节红线：
# 新增探针的消息名/方法名同步加入断言清单）。
# 正向：每个探针对外入口（class << self 里的 Citrine.debug_*）与环形缓冲
#       访问器（Debug.*_ring，定义或引用处）都必须有 exact needle 登记；
# 反向：每个 needle 都必须命中某个探针源文件（内容或路径），防止探针改名后
#       残留失效条目（如路径在 lib/citrine/debug*/ 下即被 citrine/debug 覆盖）。
# 产物侧的实编译断言仍由 `rake prod_check` 负责（CI quality job 执行）。
require "minitest/autorun"

class DebugProdCheckTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  RAKEFILE = File.join(ROOT, "Rakefile")
  DEBUG_SOURCES = [File.join(ROOT, "lib/citrine/debug.rb")] +
                  Dir[File.join(ROOT, "lib/citrine/debug/*.rb")]

  def needles
    body = File.read(RAKEFILE)
    list = body[/needles = \[(.*?)\]/m, 1]
    flunk "Rakefile 里找不到 needles 断言清单（prod_check 被改样了？）" if list.nil?

    # 清单内整行注释不参与提取
    list = list.lines.reject { |line| line.lstrip.start_with?("#") }.join
    list.scan(/"([^"]+)"/).flatten
  end

  # class << self 区域内定义的 debug_* 方法 = 探针对外入口契约；
  # 实例级 helper（如 EventStream 私有的 debug_event_type）不属于契约——
  # 其所在文件已由同文件入口的 needle 覆盖。
  def singleton_entries(body)
    entries = []
    base = nil
    body.each_line do |line|
      if base
        if line =~ /\A( *)end\s*\z/ && Regexp.last_match(1).size == base
          base = nil
        elsif (m = line.match(/\A\s*def (debug_\w+)/))
          entries << m[1]
        end
      elsif (m = line.match(/\A( *)class << self\b/))
        base = m[1].size
      end
    end
    entries
  end

  # 探针面对外契约，与 lib/citrine/debug*.rb 实际源码同步发现——
  # 新增探针即自动纳入校验，不需要改这份测试。
  def probe_tokens
    DEBUG_SOURCES.flat_map do |file|
      body = File.read(file)
      singleton_entries(body) + body.scan(/\b(\w+_ring)\b/).flatten
    end.uniq
  end

  def test_needles_cover_every_probe_entry_and_ring
    missing = probe_tokens - needles
    assert missing.empty?,
          "探针面未登记进 Rakefile prod_check 断言清单：#{missing.join(', ')} " \
          "（新增探针必须同步登记 needle，见 DESIGN-devtools 第六节）"
  end

  def test_no_orphan_needles
    orphans = needles.reject do |needle|
      DEBUG_SOURCES.any? { |file| file.include?(needle) || File.read(file).include?(needle) }
    end
    assert orphans.empty?,
          "Rakefile needles 有失效条目（探针已改名/移除？）：#{orphans.join(', ')}"
  end

  def test_every_debug_file_is_guarded
    unguarded = DEBUG_SOURCES.reject do |file|
      body = File.read(file)
      needles.any? { |needle| file.include?(needle) || body.include?(needle) }
    end
    assert unguarded.empty?,
          "以下探针文件无任何 needle 覆盖（helper-only 文件会漏进生产产物而不被发现）：" \
          "#{unguarded.map { |f| f.sub(ROOT + '/', '') }.join(', ')}"
  end

  # 扫描器正向校验：固定契约（M1-1..M1-4 骨架）必须能被 probe_tokens 发现，
  # 防止正则失配导致 test_needles_cover_every_probe_entry_and_ring 空转通过。
  def test_probe_scan_finds_fixed_contracts
    %w[debug_write_log debug_flush_trace debug_event_stream debug_component_tree].each do |name|
      assert_includes probe_tokens, name
    end
  end

  def test_legacy_needles_still_present
    %w[debug_dependency_graph debug_tracking citrine/debug].each do |needle|
      assert_includes needles, needle
    end
  end
end
