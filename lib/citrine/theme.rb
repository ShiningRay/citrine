# frozen_string_literal: true

module Citrine
  # 主题 token 与全局样式资产（S2-5 后半）：
  #
  #   Citrine.theme(color_primary: "#667eea", spacing_md: 12)
  #   Citrine.css("styles.css")     # 声明样式表：dev server 注入 <link>，打包器随包复制
  #   Citrine.css_text = <<~CSS     # 媒体查询 / 伪类等内联样式表达不了的逃生舱
  #     .card:hover { background: #f1f5f9; }
  #   CSS
  #
  # style 里用 Citrine.token(:name) 引用 token，归一化时解析：
  #   label(style: { background: Citrine.token(:color_primary),
  #                  padding: Citrine.token(:spacing_md) })
  # 数值 token 走同一套 px 推断；未定义的 token 当场报错（不静默变成裸字符串）。
  module Theme
    # token 引用：Style.normalize 遇到它时查主题注册表
    class Ref
      attr_reader :name

      def initialize(name)
        @name = name.to_sym
      end

      def inspect = "#<Citrine::Theme::Ref #{@name}>"
      def to_s = "token(#{@name})"
    end

    class << self
      def registry
        @registry ||= {}
      end

      def define(**tokens)
        registry.merge!(tokens)
        self
      end

      # 解析 token 引用；未定义的 token 属于样式错误，当场报
      def resolve!(ref)
        raise ArgumentError, "未定义的主题 token: #{ref.name}（先 Citrine.theme(#{ref.name}: ...)）" unless registry.key?(ref.name)

        registry[ref.name]
      end
    end
  end

  class << self
    # 定义 / 读取主题 token：Citrine.theme(color_primary: "#667eea")；
    # 无参调用返回注册表快照
    def theme(**tokens)
      return Theme.registry.dup if tokens.empty?

      Theme.define(**tokens)
    end

    # style 里引用主题 token
    def token(name)
      Theme::Ref.new(name)
    end

    # 声明样式表文件（相对应用根）：dev server 注入 <link>、打包器随包复制
    def css(*files)
      css_files.concat(files.map(&:to_s))
      self
    end

    def css_files
      @css_files ||= []
    end

    attr_writer :css_files

    # 自定义 CSS 文本（媒体查询 / 伪类等内联样式表达不了的东西的逃生舱）：
    # dev server 注入 <style>；SSR / 模板侧经 stylesheet_tags 输出
    def css_text
      @css_text
    end

    def css_text=(text)
      @css_text = text.to_s
    end

    # SSR / 模板侧：产出 <link> / <style> 标签串
    def stylesheet_tags
      tags = css_files.map { |f| %(<link rel="stylesheet" href="/#{f}">) }
      tags << "<style>#{css_text}</style>" if css_text && !css_text.empty?
      tags.join("\n")
    end

    # 测试与多页面隔离用：清空样式资产与主题
    def reset_style_assets!
      @css_files = []
      @css_text = nil
      Theme.registry.clear
      self
    end
  end
end
