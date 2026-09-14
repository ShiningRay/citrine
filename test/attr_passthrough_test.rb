# frozen_string_literal: true

# S2-2：属性透传——框架未消费的属性原样到达 DOM / SSR，不再静默丢弃；
# S2-4（SSR 侧）：受控 checked 的 Signal 解包、text_input 的 type 覆写。
# DOM 侧行为由 examples/props_widgets + Node 桩验收。
require "minitest/autorun"
require "citrine"
require "citrine/string_renderer"

class AttrPassthroughTest < Minitest::Test
  def widget_class(&view)
    Class.new(Citrine::Component) do
      define_method(:view, &view)
    end
  end

  def test_ssrs_passes_unknown_attributes_through
    widget = widget_class do
      button(id: "ok", disabled: true, aria_label: "提交", data_role: "primary") { "发送" }
    end

    html = Citrine.render(widget.new)
    assert_includes html, '<button id="ok" disabled aria-label="提交" data-role="primary">',
                    "未知属性不再被静默丢弃：id/disabled/aria-*/data-* 都应出现在标签上"
  end

  def test_false_and_nil_attributes_are_omitted
    widget = widget_class do
      button(id: "b", disabled: false, title: nil) { "发送" }
    end

    html = Citrine.render(widget.new)
    assert_includes html, "<button id=\"b\">", "false / nil 不输出属性"
    refute_includes html, "disabled"
    refute_includes html, "title"
  end

  def test_attribute_values_are_escaped
    widget = widget_class do
      box(title: 'a" onclick="alert(1)') { label { "x" } }
    end

    html = Citrine.render(widget.new)
    assert_includes html, %(title="a&quot; onclick=&quot;alert(1)"),
                    "透传属性值必须转义（属性注入）"
    refute_includes html, %(title="a" onclick="alert(1)")
  end

  def test_passthrough_props_unit_contract
    renderer = Citrine::StringRenderer.new
    node = Citrine::Node.new(:box, {
      id: "x", aria_label: "标签", data_role: "cell", feature_flag: true,
      hidden: false, gone: nil, on_click: -> {}, css_class: "c",
      style: { color: "red" }, key: "k", value: "v"
    }, nil, owner: nil)

    pairs = renderer.send(:passthrough_props, node)
    assert_equal [
      ["id", "x"], ["aria-label", "标签"], ["data-role", "cell"], ["feature-flag", ""], ["value", "v"]
    ], pairs, "snake_case → kebab-case；true → 空值属性；false/nil/事件/消费面不透传"
  end

  def test_text_input_type_override
    widget = widget_class do
      text_input(value: "秘密", type: "password")
    end

    assert_includes Citrine.render(widget.new), 'type="password"'
  end

  def test_check_box_ssr_reflects_signal_checked_value
    widget = Class.new(Citrine::Component) do
      state :agreed, default: false

      def view
        stack do
          check_box(checked: signal(:agreed))
        end
      end
    end.new

    refute_includes Citrine.render(widget), "checked", "Signal 为假值时不该输出 checked"

    widget.agreed = true

    assert_includes Citrine.render(widget), "checked", "Signal 为真值时输出 checked"
  end
end
