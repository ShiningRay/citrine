# frozen_string_literal: true

# T-A4：框架专属 lint cop 的验收夹具。
# 故意包含一处裸 @ivar 赋值（@count = 1）——test/cop_test.rb 断言 cop 命中它，
# 且不误伤普通类与类体上的合法 ivar。
class FixtureCounter < Citrine::Component
  state :n, default: 0

  def bump
    @count = 1 # ← 应被 Citrine/NoRawIvarAssignment 命中
    self.n += 1
  end

  def view
    label { "n=#{n}" }
  end
end

class FixturePlain < Citrine::Component
  def view = label { "plain" }
end
