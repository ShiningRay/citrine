# frozen_string_literal: true

require "minitest/autorun"

require "citrine/dev_server"

# `citrine dev` 的命令行解析（跨仓库示例用 -I 补加载路径，见 PR：dev 支持 -I）
class DevServerArgsTest < Minitest::Test
  def parse(*args)
    Citrine::DevServer.parse_args(args)
  end

  def test_defaults
    assert_equal ["examples", 4402, []], parse
  end

  def test_dir_and_port
    assert_equal ["app", 5000, []], parse("app", "-p", "5000")
  end

  def test_extra_lib_space_form
    assert_equal ["examples", 4402, ["../some-lib/lib"]], parse("-I", "../some-lib/lib")
  end

  def test_extra_lib_attached_form
    assert_equal ["examples", 4402, ["./vendor/lib"]], parse("-I./vendor/lib")
  end

  def test_extra_lib_repeatable_and_mixed_with_dir
    dir, port, libs = parse("app", "-I", "a/lib", "-p", "5000", "-Ib/lib")
    assert_equal ["app", 5000, ["a/lib", "b/lib"]], [dir, port, libs]
  end

  def test_extra_lib_without_value_raises_clear_error
    error = assert_raises(ArgumentError) { parse("-I") }
    assert_match(/需要一个加载路径参数/, error.message)
  end

  def test_extra_lib_value_looking_like_flag_raises
    assert_raises(ArgumentError) { parse("-I", "-p") }
  end

  # 额外加载路径在构造时转绝对路径：编译 cwd 是源文件所在目录，相对路径会解析错位
  def test_extra_libs_resolved_to_absolute_paths
    server = Citrine::DevServer.new("examples", 4402, ["../some-lib/lib"])
    libs = server.instance_variable_get(:@extra_libs)

    assert_equal 1, libs.length
    assert libs.first.start_with?("/"), "应转成绝对路径，实际 #{libs.first.inspect}"
    assert libs.first.end_with?("/some-lib/lib")
  end
end
