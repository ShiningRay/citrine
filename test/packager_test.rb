# frozen_string_literal: true

# D4（packager 部分）：打包器纯函数单测——app 名派生、Info.plist 生成、缺文件 abort。
# 全部离线可验：不触发真实编译（opal / swiftc 不在单测范围）。
require "minitest/autorun"
require "tmpdir"
require "citrine/packager"

class PackagerPureTest < Minitest::Test
  def app_name_for(name)
    Citrine::Packager.new(name, dir: "examples").instance_variable_get(:@app_name)
  end

  def test_app_name_derivation
    assert_equal "CitrineCounter", app_name_for("counter")
    assert_equal "CitrineTodoList", app_name_for("todo_list")
  end

  def test_info_plist_uses_gem_version_and_app_name
    plist = Citrine::Packager.new("counter", dir: "examples").send(:info_plist)

    assert_includes plist, "<key>CFBundleName</key>"
    assert_includes plist, "<string>CitrineCounter</string>"
    assert_includes plist, "<string>#{Citrine::VERSION}</string>"
    refute_includes plist, "<string>0.1.0</string>", "版本必须跟随 Citrine::VERSION，不再硬编码"
    assert_includes plist, "dev.rubyreact.citrinecounter"
  end

  def test_missing_files_abort_with_actionable_message
    Dir.mktmpdir do |dir|
      packager = Citrine::Packager.new("nope", dir: dir)
      _out, err = capture_io do
        assert_raises(SystemExit) { packager.package }
      end

      assert_match(/找不到/, err)
      assert_match(/nope\.rb/, err)
    end
  end

  def test_run_without_name_aborts_with_usage
    _out, err = capture_io do
      assert_raises(SystemExit) { Citrine::Packager.run!([]) }
    end

    assert_match(/用法/, err)
  end

  def test_opal_executable_resolves_via_rubygems_or_falls_back
    bin = Citrine::Packager.new("counter", dir: "examples").send(:opal_executable)

    assert_kind_of String, bin
    assert_equal "opal", File.basename(bin)
  end

  def test_parse_args_name_only
    assert_equal ["counter", "examples", [], nil], Citrine::Packager.parse_args(["counter"])
  end

  def test_parse_args_dir_and_repeatable_includes
    name, dir, extra_libs, app_name = Citrine::Packager.parse_args(
      ["desktop", "../emerald/examples", "-I", "../beryl/lib", "-I../emerald/lib"]
    )

    assert_equal "desktop", name
    assert_equal "../emerald/examples", dir
    assert_equal ["../beryl/lib", "../emerald/lib"], extra_libs
    assert_nil app_name
  end

  def test_parse_args_app_name_override
    _name, _dir, _extra_libs, app_name = Citrine::Packager.parse_args(["desktop", "-n", "Emerald"])

    assert_equal "Emerald", app_name
  end

  def test_parse_args_missing_include_value_raises
    assert_raises(ArgumentError) { Citrine::Packager.parse_args(["counter", "-I"]) }
  end

  def test_app_name_override_wins_over_derivation
    packager = Citrine::Packager.new("desktop", dir: "examples", app_name: "Emerald")

    assert_equal "Emerald", packager.instance_variable_get(:@app_name)
  end

  def test_extra_libs_expanded_to_absolute_paths
    packager = Citrine::Packager.new("desktop", dir: "examples", extra_libs: ["../beryl/lib"])

    assert_equal [File.expand_path("../beryl/lib")],
                 packager.instance_variable_get(:@extra_libs)
  end
end
