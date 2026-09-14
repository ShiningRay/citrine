# frozen_string_literal: true

# S2-5 后半：主题 token（Citrine.theme / Citrine.token）与全局样式资产
# （Citrine.css 声明样式表、Citrine.css_text 自定义样式文本）。
require "minitest/autorun"
require "citrine"
require "citrine/string_renderer"
require "citrine/dev_server"

class ThemeTokenTest < Minitest::Test
  def setup
    Citrine.reset_style_assets!
  end

  def teardown
    Citrine.reset_style_assets!
  end

  def test_token_resolves_in_style_normalize
    Citrine.theme(color_primary: "#667eea")

    normalized = Citrine::Style.normalize({ background: Citrine.token(:color_primary) })

    assert_equal({ background: "#667eea" }, normalized)
  end

  def test_numeric_token_gets_px_inference
    Citrine.theme(spacing_md: 12)

    assert_equal({ padding: "12px" }, Citrine::Style.normalize({ padding: Citrine.token(:spacing_md) }))
  end

  def test_token_can_reference_another_token
    Citrine.theme(color_primary: "#667eea", brand: Citrine.token(:color_primary))

    assert_equal({ color: "#667eea" }, Citrine::Style.normalize({ color: Citrine.token(:brand) }))
  end

  def test_undefined_token_raises
    error = assert_raises(ArgumentError) do
      Citrine::Style.normalize({ background: Citrine.token(:nope) })
    end

    assert_match(/未定义的主题 token: nope/, error.message)
  end

  def test_theme_readback
    Citrine.theme(color_primary: "#667eea")

    assert_equal({ color_primary: "#667eea" }, Citrine.theme)
  end

  def test_tokens_flow_through_ssr_and_components
    Citrine.theme(color_danger: "#b91c1c")
    widget = Class.new(Citrine::Component) do
      def view
        label(style: { color: Citrine.token(:color_danger) }) { "告警" }
      end
    end

    assert_includes Citrine.render(widget.new), "color:#b91c1c"
  end
end

class StyleAssetsTest < Minitest::Test
  def setup
    Citrine.reset_style_assets!
  end

  def teardown
    Citrine.reset_style_assets!
  end

  def server
    Citrine::DevServer.new("examples", 4402)
  end

  def inject(html)
    server.send(:inject_head_assets, html)
  end

  def test_css_declaration_injects_link_tag
    Citrine.css("styles.css", "theme-dark.css")

    html = inject("<!DOCTYPE html><html><head></head><body></body></html>")
    assert_includes html, %(<link rel="stylesheet" href="/styles.css">)
    assert_includes html, %(<link rel="stylesheet" href="/theme-dark.css">)
    assert html.index("/styles.css") < html.index("</head>"), "注入发生在 </head> 之前"
  end

  def test_css_text_injects_style_tag
    Citrine.css_text = ".card:hover { background: #f1f5f9; }"

    html = inject("<html><head></head></html>")
    assert_includes html, "<style>.card:hover { background: #f1f5f9; }</style>", "媒体查询/伪类的逃生舱"
  end

  def test_no_assets_leaves_html_untouched
    html = "<html><head></head></html>"

    assert_equal html, inject(html)
  end

  def test_stylesheet_tags_for_ssr_templates
    Citrine.css("styles.css")
    Citrine.css_text = "@media (max-width: 480px) { .page { padding: 8px; } }"

    tags = Citrine.stylesheet_tags
    assert_includes tags, %(<link rel="stylesheet" href="/styles.css">)
    assert_includes tags, "@media (max-width: 480px)"
  end
end
