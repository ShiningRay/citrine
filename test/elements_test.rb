# frozen_string_literal: true

# S2-1：元素词表 + 逃生舱——常用 HTML 元素有 DSL 方法、任意标签走 element()；
# 输出复用既有兜底（TAGS[type] || type.to_s），DOM 与 SSR 两侧一致。
require "minitest/autorun"
require "citrine"
require "citrine/string_renderer"

class ElementsTest < Minitest::Test
  def widget_class(&view)
    Class.new(Citrine::Component) do
      define_method(:view, &view)
    end
  end

  def test_element_vocabulary_renders_correct_tags
    widget = widget_class do
      ul(css_class: "list") do
        li { "一" }
        li { "二" }
      end
    end

    assert_includes Citrine.render(widget.new), '<ul class="list"><li>一</li><li>二</li></ul>'
  end

  def test_elements_take_passthrough_attributes
    widget = widget_class do
      a(href: "https://example.com", css_class: "lnk", aria_label: "官网") { "首页" }
    end

    html = Citrine.render(widget.new)
    assert_includes html, '<a class="lnk" href="https://example.com" aria-label="官网">首页</a>'
  end

  def test_img_is_void_element
    widget = widget_class do
      img(src: "/logo.png", alt: "标")
    end

    html = Citrine.render(widget.new)
    assert_includes html, '<img src="/logo.png" alt="标">'
    refute_includes html, "</img>", "img 为 void 元素，不应有闭合标签"
  end

  def test_element_escape_hatch_produces_arbitrary_tag
    widget = widget_class do
      element(:my_widget, id: "x") { label { "自定义" } }
    end

    assert_includes Citrine.render(widget.new), '<my_widget id="x"><p>自定义</p></my_widget>'
  end

  def test_element_escape_hatch_symbol_or_string
    widget = widget_class do
      stack do
        element("web-widget")
        element(:other_widget)
      end
    end

    html = Citrine.render(widget.new)
    assert_includes html, "<web-widget>"
    assert_includes html, "<other_widget>", "标签名不做大小写/连字符转换（与 type.to_s 一致）"
  end

  def test_value_passes_through_on_non_widget_elements
    widget = widget_class do
      textarea(value: "草稿", rows: "3")
    end

    html = Citrine.render(widget.new)
    assert_includes html, 'value="草稿"', "value 只在 text_input 上被消费，其余元素照常透传"
    assert_includes html, 'rows="3"'
  end

  def test_widget_value_props_still_consumed_on_widgets
    widget = Class.new(Citrine::Component) do
      state :draft, default: "预填"

      def view = text_input(value: signal(:draft))
    end

    html = Citrine.render(widget.new)
    assert_includes html, 'value="预填"'
  end
end
