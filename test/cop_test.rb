# frozen_string_literal: true

# T-A4：Citrine/NoRawIvarAssignment cop——组件内的裸 @ivar 赋值是门禁违规；
# 框架源码（lib/citrine/**）与类体上的宏内部状态不拦；普通类不误报。
require "minitest/autorun"
require "rubocop"
require_relative "../lib/rubocop/cop/citrine/no_raw_ivar_assignment"

class CopTest < Minitest::Test
  FIXTURE = File.expand_path("fixtures/cop_fixture.rb", __dir__)

  def offenses_for(source)
    processed = RuboCop::ProcessedSource.new(source, 3.1, "test.rb")
    cop = RuboCop::Cop::Citrine::NoRawIvarAssignment.new
    commissioner = RuboCop::Cop::Commissioner.new([cop])
    report = commissioner.investigate(processed)
    report.offenses
  end

  def test_flags_bare_ivar_assignment_inside_component
    offenses = offenses_for(<<~RUBY)
      class Counter < Citrine::Component
        state :n, default: 0

        def bump
          @count = 1
          self.n += 1
        end

        def view
          label { "n=\#{n}" }
        end
      end
    RUBY

    assert_equal 1, offenses.size
    assert_match(/绕过信号追踪/, offenses.first.message)
  end

  def test_flags_anonymous_component_class
    offenses = offenses_for(<<~RUBY)
      klass = Class.new(Citrine::Component) do
        def view
          box { @rows = [] }
        end
      end
    RUBY

    assert_equal 1, offenses.size
  end

  def test_does_not_flag_plain_classes
    offenses = offenses_for(<<~RUBY)
      class PlainService
        def call
          @memo = {}
          @memo
        end
      end
    RUBY

    assert_empty offenses, "普通类（非 Component）不误报"
  end

  def test_does_not_flag_reads_or_class_body_state
    offenses = offenses_for(<<~RUBY)
      class Widget < Citrine::Component
        @registry = {} # 类体（class-level）状态：不属于组件实例，不拦

        def view
          label { @registry.to_s }
        end
      end
    RUBY

    assert_empty offenses, "只拦写入：裸读与类体赋值不报"
  end

  def test_fixture_file_hits_exactly_once
    offenses = offenses_for(File.read(FIXTURE))

    assert_equal 1, offenses.size, "夹具中的 @count = 1 应被命中，其余不误报"
  end
end
