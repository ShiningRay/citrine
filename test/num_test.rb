# frozen_string_literal: true

# 跨平台数值工具（G-11）：这里的每个断言在 CRuby 与 Opal 下都必须成立。
# 同一组用例还会被 examples/num_parity.rb 在两侧各跑一遍并逐字节比对（rake parity）。
require "minitest/autorun"
require "citrine"

class NumTest < Minitest::Test
  def test_idiv_floors_towards_negative_infinity
    assert_equal 3, Citrine::Num.idiv(7, 2)
    assert_equal(-4, Citrine::Num.idiv(-7, 2))
    assert_equal(-4, Citrine::Num.idiv(7, -2))
    assert_equal 4, Citrine::Num.idiv(7.0, 1.5)
  end

  def test_round_to_rounds_halfway_away_from_zero
    assert_equal(-2, Citrine::Num.round_to(-1.5, 0))
    assert_equal 2, Citrine::Num.round_to(1.5, 0)
    assert_equal(-3, Citrine::Num.round_to(-2.5, 0))
    assert_equal(-1.3, Citrine::Num.round_to(-1.25, 1))
    assert_equal(-1.4, Citrine::Num.round_to(-1.35, 1))
    assert_equal(-2.68, Citrine::Num.round_to(-2.675, 2))
  end

  def test_round_to_keeps_non_halfway_values_and_negative_precision
    assert_equal(-1, Citrine::Num.round_to(-1.4, 0))
    assert_equal(-3, Citrine::Num.round_to(-2.8, 0))
    assert_equal 123_500, Citrine::Num.round_to(123_456.78, -2)
    assert_equal(-1.23, Citrine::Num.round_to(-1.234, 2))
  end

  def test_round_alias
    assert_equal(-3, Citrine::Num.round(-2.5))
    assert_equal 0, Citrine::Num.round(0.49999999999999994)
  end

  # 返回类型必须与 MRI 对齐（迁移真实应用时踩到：Num.round(2.0) 若返回 Float，
  # 显示层会渲染成 "2.0" 而不是 "2"）
  def test_return_types_match_mri
    assert_instance_of Integer, Citrine::Num.round(2.0)
    assert_instance_of Integer, Citrine::Num.round(-2.5)
    assert_instance_of Integer, Citrine::Num.round_to(123_456.78, -2)
    assert_instance_of Float, Citrine::Num.round_to(1.25, 1)
    assert_equal "2", Citrine::Num.round(2.0).to_s
    assert_equal "123500", Citrine::Num.round_to(123_456.78, -2).to_s
  end

  def test_integral_predicate
    assert Citrine::Num.integral?(2)
    assert Citrine::Num.integral?(2.0)
    refute Citrine::Num.integral?(2.5)
  end

  def test_finite_predicate
    assert Citrine::Num.finite?(1)
    assert Citrine::Num.finite?(-2.5)
    refute Citrine::Num.finite?(Float::INFINITY)
    refute Citrine::Num.finite?(Float::NAN)
    refute Citrine::Num.finite?("12"), "非 Numeric 一律 false"
  end

  def test_percent_formatting
    assert_equal "12.3%", Citrine::Num.percent(0.1234, 1)
    assert_equal "-12.3%", Citrine::Num.percent(-0.1234, 1)
  end
end
