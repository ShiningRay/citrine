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

    def normalize(style)
      return {} unless style

      style.each_with_object({}) do |(key, value), out|
        out[underscore(key)] = normalize_value(value)
      end
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
