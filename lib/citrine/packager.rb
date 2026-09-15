# frozen_string_literal: true

# Citrine 打包器：把示例打成双击可运行的桌面应用
#   macOS：build/<Name>.app/{MacOS/<Name>, Resources/{index.html, <name>.js}, Info.plist}
#   Windows：build/<Name>.win/{<Name>.cmd, launch.ps1, index.html, <name>.js}
#           （零依赖壳：Edge --app 模式打开，Win10/11 自带 Edge；无窗口边框地址栏）
require "open3"
require "fileutils"
require_relative "version"

module Citrine
  class Packager
    def self.run!(args)
      if args.empty?
        abort <<~USAGE
          用法: bin/citrine package <示例名>
          示例: bin/citrine package counter   # 打包 examples/counter
        USAGE
      end
      new(args.first).package
    end

    def initialize(name, dir: "examples")
      @name = name
      @dir = File.expand_path(dir)
      @root = File.expand_path("../..", __dir__)
      @app_name = "Citrine" + @name.split("_").map(&:capitalize).join
    end

    def package
      rb = File.join(@dir, "#{@name}.rb")
      html_path = File.join(@dir, "#{@name}.html")
      abort "找不到 #{rb} 或 #{html_path}" unless File.exist?(rb) && File.exist?(html_path)

      win = Gem.win_platform?
      app_dir = File.join(@root, "build", win ? "#{@app_name}.win" : "#{@app_name}.app")
      FileUtils.rm_rf(app_dir)
      res_dir = win ? app_dir : File.join(app_dir, "Contents", "Resources")
      FileUtils.mkdir_p(res_dir)

      puts "[package] 编译 #{@name}.rb …"
      js = File.join(res_dir, "#{@name}.js")
      compile_js(rb, js)

      puts "[package] 复制资源 …"
      FileUtils.cp(html_path, File.join(res_dir, "index.html"))
      # S2-5：样式表随包复制（应用声明的 Citrine.css 文件与目录内 *.css）
      Dir.glob(File.join(@dir, "*.css")).each do |css|
        FileUtils.cp(css, res_dir)
        puts "  + #{File.basename(css)}"
      end

      if win
        puts "[package] 生成 Windows 壳（Edge --app 零依赖模式）…"
        write_windows_launcher(app_dir)
        puts "[package] 完成 → #{app_dir}"
        puts "  运行: 双击 #{File.join(app_dir, "#{@app_name}.cmd")}"
        puts "  开发模式: #{File.join(app_dir, "#{@app_name}.cmd")} --dev http://localhost:4402/#{@name}.html（需先 bin/citrine dev）"
      else
        macos_dir = File.join(app_dir, "Contents", "MacOS")
        FileUtils.mkdir_p(macos_dir) # swiftc 不会自建输出目录（macOS 打包冒烟的 ld errno=2 即缺此）
        puts "[package] 编译 Swift 壳 …"
        exe = File.join(macos_dir, @app_name)
        swift_build(exe)

        File.write(File.join(app_dir, "Contents", "Info.plist"), info_plist)
        puts "[package] 完成 → #{app_dir}"
        puts "  运行: open #{app_dir}"
        puts "  开发模式: #{exe} --dev http://localhost:4402/#{@name}.html（需先 bin/citrine dev）"
      end
      app_dir
    end

    private

    def compile_js(rb, output)
      # Windows 无法直接 spawn 无扩展名的 binstub（POSIX sh 脚本），经 Gem.ruby 调起
      command = Gem.win_platform? ? [Gem.ruby, opal_executable] : [opal_executable]
      out, err, status = Open3.capture3(
        *command, "-c",
        "-I#{File.join(@root, 'lib')}", "-I#{@dir}",
        "-o", output, File.basename(rb),
        chdir: @dir
      )
      return if status.success?

      abort "编译失败:\n#{out}\n#{err}"
    rescue Errno::ENOENT
      abort "找不到 opal 可执行文件：请先 bundle install，并用 bundle exec bin/citrine package 打包"
    end

    # Windows 壳：cmd 启动器 + PowerShell 脚本（构建 file:// URI、定位 Edge，
    # 找不到 Edge 时退化为系统默认浏览器打开）
    def write_windows_launcher(app_dir)
      cmd = <<~CMD
        @echo off
        powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0launch.ps1" %*
      CMD
      File.write(File.join(app_dir, "#{@app_name}.cmd"), cmd)

      ps1 = <<~PS1
        # Citrine Windows 壳：Edge --app 模式（无边框应用窗口）
        # $Mode 占位承接 --dev 标记，URL 走下一个参数（无参时用包内 index.html）
        # 独立 user-data-dir：复用默认配置时 --app 会被已有实例/启动加速
        # 接管成普通标签页；独立配置强制新实例，才有应用窗口形态
        param([string]$Mode, [string]$Url)
        $dir = Split-Path -Parent $MyInvocation.MyCommand.Path
        if (-not $Url) { $Url = (New-Object System.Uri((Join-Path $dir 'index.html'))).AbsoluteUri }
        $edge = @("${env:ProgramFiles(x86)}", "$env:ProgramFiles") |
          ForEach-Object { Join-Path $_ 'Microsoft\\Edge\\Application\\msedge.exe' } |
          Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($edge) {
          $profile = Join-Path $env:LOCALAPPDATA 'Citrine\\#{@app_name}'
          Start-Process $edge -ArgumentList "--app=$Url", "--user-data-dir=$profile", "--no-first-run"
        } else { Start-Process $url }
      PS1
      File.write(File.join(app_dir, "launch.ps1"), ps1)
    end

    def swift_build(output)
      out, err, status = Open3.capture3(
        "swiftc", "-framework", "Cocoa", "-framework", "WebKit",
        "-o", output, File.join(@root, "desktop", "main.swift")
      )
      return if status.success?

      abort "Swift 编译失败:\n#{out}\n#{err}"
    rescue Errno::ENOENT
      abort "找不到 swiftc：打包 macOS .app 需要 Xcode 命令行工具（xcode-select --install）"
    end

    # A5：经 rubygems 解析 opal 的 binstub（bundler 环境下稳定指向 bundle 内的 opal）；
    # 解析不到退化为 PATH 查找——真缺失时由 Errno::ENOENT 分支给出可操作的 abort 提示
    def opal_executable
      Gem.bin_path("opal", "opal")
    rescue Gem::LoadError
      "opal"
    end

    def info_plist
      <<~PLIST
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>CFBundleName</key>
          <string>#{@app_name}</string>
          <key>CFBundleDisplayName</key>
          <string>#{@app_name}</string>
          <key>CFBundleIdentifier</key>
          <string>dev.rubyreact.#{@app_name.downcase}</string>
          <key>CFBundleVersion</key>
          <string>#{Citrine::VERSION}</string>
          <key>CFBundleShortVersionString</key>
          <string>#{Citrine::VERSION}</string>
          <key>CFBundlePackageType</key>
          <string>APPL</string>
          <key>CFBundleExecutable</key>
          <string>#{@app_name}</string>
          <key>LSMinimumSystemVersion</key>
          <string>11.0</string>
          <key>NSHighResolutionCapable</key>
          <true/>
          <key>NSPrincipalClass</key>
          <string>NSApplication</string>
        </dict>
        </plist>
      PLIST
    end
  end
end
