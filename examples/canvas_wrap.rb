# frozen_string_literal: true

# T-B2 示例：Canvas 文本换行——style width 约束下贪心断行（CJK 逐字、拉丁按词）
require "citrine/canvas"

class WrapProbe < Citrine::Component
  def view
    stack do
      label(css_class: "wrap", style: { width: "42px" }) { "甲乙丙丁戊己庚辛壬癸" }
      label { "单行不换行" }
    end
  end
end

Citrine::CanvasRenderer.mount_at("app", WrapProbe.new)
