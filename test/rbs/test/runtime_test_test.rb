require "test_helper"
require "rbs/test"
require "logger"

return unless Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.7.0')

module TestSetupHelper
  include TestHelper

  def do_runtime_session(other_env: {})
    SignatureManager.new(system_builtin: true) do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
class Hello
  attr_reader x: Integer
  attr_reader y: Integer

  def initialize: (x: Integer, y: Integer) -> void

  def move: (?x: Integer, ?y: Integer) -> void
end
EOF
      manager.build do |env, path|
        (path + "sample.rb").write(<<RUBY)
class Hello
  attr_reader :x, :y

  def initialize(x:, y:)
    @x = x
    @y = y
  end

  def move(x: 0, y: 0)
    @x += x
    @y += y
  end
end

hello = Hello.new(x: 0, y: 10)
hello.move(y: -10)
hello.move(10, -20)
RUBY

        env = {
          "BUNDLE_GEMFILE" => File.join(__dir__, "../../../Gemfile"),
          "RBS_TEST_TARGET" => "::Hello",
          "RBS_TEST_OPT" => "-I./foo.rbs"
        }
        _out, err, status = Open3.capture3(env.merge(other_env), "ruby", "-rbundler/setup", "-rrbs/test/setup", "sample.rb", chdir: path.to_s)

        # STDOUT.puts _out
        # STDERR.puts err

        refute_operator status, :success?

        err
      end
    end
  end

  def assert_runtime_session(other_env: {})
    err = do_runtime_session(other_env: other_env)

    assert_match(/Setting up hooks for ::Hello$/, err)
    assert_match(/TypeError: \[Hello#move\] ArgumentError:/, err)
  end

  def assert_exit(other_env: {})
    err = do_runtime_session(other_env: other_env)
    assert_match(/E, .+ ERROR -- rbs: Sample size should be a positive integer: `.+`\n/, err)
  end
end

class RBS::Test::RuntimeTestTest < Minitest::Test
  include TestSetupHelper

  def test_runtime_test 
    assert_runtime_session
  end

  def test_get_sample_size
    assert_runtime_session(other_env: {'RBS_TEST_SAMPLE_SIZE' => '100'})
    assert_runtime_session(other_env: {'RBS_TEST_SAMPLE_SIZE' => '50'})
    assert_runtime_session(other_env: {'RBS_TEST_SAMPLE_SIZE' => 'ALL'})

    assert_exit(other_env: {'RBS_TEST_SAMPLE_SIZE' => 'FOO'})
    assert_exit(other_env: {'RBS_TEST_SAMPLE_SIZE' => '0'})
    assert_exit(other_env: {'RBS_TEST_SAMPLE_SIZE' => '-1'})
  end
end
