# frozen_string_literal: true

module Citrine
  # 样式键归一化（决策 #10）：
  # - API 层统一 snake_case（Ruby 惯例，与 on_click 等事件命名同风格）
  # - 兼容 camelCase 输入（fontSize 与 font_size 等价）
  # - 值中的 Symbol 自动转 CSS 连字符形式（:line_through → "line-through"）
  # 各渲染器在边界自行编译：DOM → camelCase 属性；CSS 字符串 → kebab-case；
  # Canvas 直接以 snake_case 消费。
  module Style
    module_function

    # 有数值默认补 px 的属性（显式字符串单位不受影响）。
    # font_size 等排版键在此的原因：CSS 里 `font-size:14` 是非法声明（浏览器整条丢弃），
    # SSR 按值直拼会输出非法 CSS——数值必须推断成 "14px" 才与 DOM 侧一致。
    PX_PROPERTIES = %i[
      width height min_width min_height max_width max_height
      border_radius top left right bottom inset
      padding padding_left padding_right padding_top padding_bottom
      margin margin_left margin_right margin_top margin_bottom
      font_size letter_spacing word_spacing text_indent
      gap row_gap column_gap outline_width outline_offset
    ].freeze

    # 数值语义上无单位的属性
    UNITLESS_PROPERTIES = %i[
      flex flex_grow flex_shrink order opacity z_index line_height
      font_weight column_count zoom
    ].freeze

    def normalize(style)
      return {} unless style

      style.each_with_object({}) do |(key, value), out|
        key = underscore(key)
        value = resolve_theme_ref(value)
        value = normalize_value(value)
        next if value.nil? # F17：nil 值剔除而非输出非法 CSS
        if value.is_a?(Numeric) && PX_PROPERTIES.include?(key) && !UNITLESS_PROPERTIES.include?(key)
          value = "#{value}px"
        end
        out[key] = value
      end
    end

    # 主题 token 引用（S2-5）→ 主题值。token 值还可以再引用 token
    # （有深度上限防循环引用）；解析后的数值走同一套 px 推断
    def resolve_theme_ref(value, depth = 0)
      return value unless value.is_a?(Theme::Ref)
      raise ArgumentError, "主题 token 嵌套过深（疑似循环引用）" if depth > 8

      resolve_theme_ref(Theme.resolve!(value), depth + 1)
    end

    # fontSize / font_size / :fontSize → :font_size
    def underscore(key)
      key.to_s.gsub(/([A-Z])/) { "_#{Regexp.last_match(1).downcase}" }.downcase.to_sym
    end

    # font_size → fontSize（DOM style 属性赋值用）
    def camel(key)
      key.to_s.gsub(/_([a-zA-Z0-9])/) { Regexp.last_match(1).upcase }
    end

    # font_size → font-size（内联 CSS 字符串用）
    def kebab(key)
      key.to_s.tr("_", "-")
    end

    def normalize_value(value)
      value.is_a?(Symbol) ? value.to_s.tr("_", "-") : value
    end
  end
end
