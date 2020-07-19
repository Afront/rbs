require "test_helper"
require "rbs/test"

class SetupTest < Minitest::Test
include RBS::Test::SetupHelper

  def test_get_sample_size
    assert_equal 100, get_sample_size("100")
    assert_equal 100, get_sample_size(nil)
    assert_nil get_sample_size("ALL")

    Array.new(1000) { |i| i.succ.to_s}.each do |i|
      assert_equal i.to_i, get_sample_size(i)
    end

    assert_raises InvalidSampleSizeError do
      get_sample_size("yes")
    end

    assert_raises InvalidSampleSizeError do
      get_sample_size('0')
    end

    assert_raises InvalidSampleSizeError do
      get_sample_size('-1')
    end
  end
end

