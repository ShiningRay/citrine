# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "tmpdir"

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

  # A6：-p 缺参与 -I 同口径 fail fast，不再静默吞掉（args[i+1] 为 nil 时 to_i 变 0）
  def test_port_without_value_raises_clear_error
    error = assert_raises(ArgumentError) { parse("-p") }
    assert_match(/需要一个端口参数/, error.message)
  end

  def test_port_value_looking_like_flag_raises
    assert_raises(ArgumentError) { parse("-p", "-I") }
  end

  def test_unknown_flag_warns_and_is_skipped
    parsed = nil
    _out, err = capture_io { parsed = parse("--bogus", "app") }

    assert_match(/未知参数 --bogus/, err)
    assert_equal ["app", 4402, []], parsed
  end
end

# A4：静态文件路由的目录逃逸守卫（前缀匹配挡不住 ../ 与同名前缀兄弟目录）
class DevServerFileGuardTest < Minitest::Test
  def setup
    @base = Dir.mktmpdir
    @dir = File.join(@base, "a")
    Dir.mkdir(@dir)
    File.write(File.join(@dir, "app.rb"), "puts 1")
    @server = Citrine::DevServer.new(@dir, 4402)
  end

  def teardown
    FileUtils.remove_entry(@base) if @base && File.directory?(@base)
  end

  def test_serves_file_inside_dir
    status, _headers, body = @server.send(:route_file, "/app.rb")

    assert_equal 200, status
    assert_equal "puts 1", body.join
  end

  def test_parent_directory_escape_is_rejected
    File.write(File.join(@base, "secret.txt"), "secret")

    status, = @server.send(:route_file, "/../secret.txt")

    assert_equal 404, status
  end

  def test_sibling_with_dir_name_prefix_is_rejected
    # @dir = .../a 时，.../a-evil/x.txt 命中旧守卫的 start_with?(@dir)，必须被拦下
    sibling = "#{@dir}-evil"
    Dir.mkdir(sibling)
    File.write(File.join(sibling, "x.txt"), "x")

    status, = @server.send(:route_file, "/../#{File.basename(sibling)}/x.txt")

    assert_equal 404, status
  end
end

# T6：SSE 僵尸连接——写失败即清扫；ping 帧只作心跳，不占消息位
class DevServerSseSweepTest < Minitest::Test
  def test_broken_connection_is_removed_on_write_failure
    server = Citrine::DevServer.new("examples", 4402)
    queue = Queue.new
    clients = server.instance_variable_get(:@clients)
    server.instance_variable_get(:@mutex).synchronize { clients << queue }

    broken = Object.new
    def broken.write(*) = raise(IOError, "closed stream")

    pump = Thread.new { server.send(:pump_client, broken, queue) }
    queue << "reload"
    deadline = Time.now + 2
    sleep 0.005 until clients.empty? || Time.now > deadline
    pump.join(2)

    assert_empty clients, "写失败的 SSE 连接应立即从注册表清扫"
  end

  def test_pump_writes_ping_frame_as_comment
    server = Citrine::DevServer.new("examples", 4402)
    queue = Queue.new
    io = StringIO.new

    pump = Thread.new { server.send(:pump_client, io, queue) }
    queue << :ping
    queue << "reload"
    deadline = Time.now + 2
    sleep 0.005 until io.string.include?("data: reload") || Time.now > deadline
    queue.close
    pump.join(2)

    assert_includes io.string, ": ping\n\n"
    assert_includes io.string, "data: reload\n\n"
  end
end
