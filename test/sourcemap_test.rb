# frozen_string_literal: true

# T-B3 后半（本地验收）：把 Opal 产物的 JS 抛错位置还原到 .rb 文件与行号。
# 支持 Indexed source map（Opal 产出形态）。Sentry 上报接入需外部账号，
# 本测试验证同一核心能力：一条测试异常 → 还原到 .rb 行号。
require "minitest/autorun"
require "tmpdir"
require "citrine"

class SourceMapVLQTest < Minitest::Test
  def sm
    Citrine::SourceMap.new({})
  end

  def test_decode_vlq_single_fields
    assert_equal [0], sm.send(:decode_vlq, "A")
    assert_equal [1], sm.send(:decode_vlq, "C")
    assert_equal [2], sm.send(:decode_vlq, "E")
    assert_equal [-1], sm.send(:decode_vlq, "D")
    assert_equal [0, 0, 0, 0], sm.send(:decode_vlq, "AAAA")
  end
end

class SourceMapLocateTest < Minitest::Test
  def test_locate_simple_map
    sm = Citrine::SourceMap.new({
      "version" => 3,
      "sources" => ["a.rb"],
      "mappings" => ";;AAAA;AACA" # 第 3 行 → a.rb:1；第 4 行 → a.rb:2
    })

    assert_equal "a.rb", sm.locate(3, 0)[:source]
    assert_equal 1, sm.locate(3, 0)[:line]
    assert_equal 2, sm.locate(4, 0)[:line]
    assert_nil sm.locate(2, 0), "无映射的行返回 nil"
  end

  def test_locate_indexed_map
    sm = Citrine::SourceMap.new({
      "version" => 3,
      "sections" => [
        {"offset" => {"line" => 0, "column" => 0},
         "map" => {"sources" => ["a.rb"], "mappings" => "AAAA;AAAA"}},
        {"offset" => {"line" => 10, "column" => 0},
         "map" => {"sources" => ["b.rb"], "mappings" => "AAAA;AACA"}}
      ]
    })

    assert_equal "a.rb", sm.locate(1, 0)[:source]
    assert_equal "a.rb", sm.locate(2, 0)[:source]
    # section2 offset line=10 为 0-based：覆盖 1-based 第 11 行起
    assert_equal "b.rb", sm.locate(11, 0)[:source]
    assert_equal 1, sm.locate(11, 0)[:line]
    assert_equal 2, sm.locate(12, 0)[:line]
    assert_nil sm.locate(10, 0), "section 起始之前的生成行无映射"
    assert_equal %w[a.rb b.rb], sm.sources
  end
end

class SourceMapEndToEndTest < Minitest::Test
  def test_raised_error_restored_to_rb_line
    Dir.mktmpdir do |dir|
      rb = File.join(dir, "raise_sample.rb")
      File.write(rb, <<~RUBY)
        # raise_sample：异常发生在第 3 行
        x = 1
        raise "boom-tb3"
      RUBY
      js = File.join(dir, "raise_sample.js")
      ok = system("opal", "-c", "-I", "lib", "-o", js, rb, out: File::NULL, err: File::NULL)
      skip "opal 不可用" unless ok

      stderr = `node #{js} 2>&1`
      frames = stderr.scan(/raise_sample\.js:(\d+):(\d+)/)
      skip "无法从栈中取得 js 位置" if frames.empty?

      map = Citrine::SourceMap.load(js)
      restored = frames.map { |(line, col)| map.locate(line.to_i, col.to_i) }
                       .compact
                       .select { |loc| loc[:source].end_with?("raise_sample.rb") }

      assert restored.any? { |loc| loc[:line] == 3 },
             "异常栈应能还原到 raise_sample.rb 第 3 行，实际 #{restored.map { |l| l[:line] }.inspect}"
    end
  end
end
