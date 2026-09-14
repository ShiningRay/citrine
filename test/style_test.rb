# frozen_string_literal: true

# Style 单位推断（S2-5 前半）：数值键按属性推断 px；显式单位不动；无单位键不受影响。
require "minitest/autorun"
require "citrine"
require "citrine/string_renderer"

class StyleTest < Minitest::Test
  def test_numeric_font_size_infers_px
    assert_equal({ font_size: "14px" }, Citrine::Style.normalize({ font_size: 14 }))
  end

  def test_explicit_units_pass_through
    assert_equal({ font_size: "1.2em" }, Citrine::Style.normalize({ font_size: "1.2em" }))
    assert_equal({ letter_spacing: "0.5rem" }, Citrine::Style.normalize({ letter_spacing: "0.5rem" }))
  end

  def test_long_tail_typography_and_gap_keys_infer_px
    normalized = Citrine::Style.normalize(
      { letter_spacing: 1, word_spacing: 2, text_indent: 8,
        gap: 4, row_gap: 5, column_gap: 6, outline_width: 2, outline_offset: 3 }
    )
    assert_equal "1px", normalized[:letter_spacing]
    assert_equal "2px", normalized[:word_spacing]
    assert_equal "8px", normalized[:text_indent]
    assert_equal "4px", normalized[:gap]
    assert_equal "5px", normalized[:row_gap]
    assert_equal "6px", normalized[:column_gap]
    assert_equal "2px", normalized[:outline_width]
    assert_equal "3px", normalized[:outline_offset]
  end

  def test_unitless_keys_stay_unitless
    normalized = Citrine::Style.normalize({ line_height: 1.5, font_weight: 600, flex: 1, opacity: 0.5 })
    assert_equal 1.5, normalized[:line_height]
    assert_equal 600, normalized[:font_weight]
    assert_equal 1, normalized[:flex]
    assert_equal 0.5, normalized[:opacity]
  end

  def test_camelcase_font_size_compat
    # camelCase 兼容输入同样推断（fontSize → font_size → "14px"）
    assert_equal({ font_size: "14px" }, Citrine::Style.normalize({ fontSize: 14 }))
  end

  def test_ssr_outputs_valid_px_declaration
    widget = Class.new(Citrine::Component) do
      def view
        label(style: { font_size: 14 }) { "x" }
      end
    end
    html = Citrine.render(widget.new)
    assert_includes html, "font-size:14px", "SSR 必须输出合法 CSS（裸数值会被浏览器整条丢弃）"
    refute_includes html, "font-size:14;"
  end

  def test_ssr_keeps_explicit_unit
    widget = Class.new(Citrine::Component) do
      def view
        label(style: { font_size: "1.2em" }) { "x" }
      end
    end
    assert_includes Citrine.render(widget.new), "font-size:1.2em"
  end
end
