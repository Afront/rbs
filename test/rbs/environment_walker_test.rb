require "test_helper"

class RBS::EnvironmentWalkerTest < Minitest::Test
  include TestHelper

  Environment = RBS::Environment
  EnvironmentLoader = RBS::EnvironmentLoader
  EnvironmentWalker = RBS::EnvironmentWalker

  def test_sort
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
class Hello
  def foo: (Symbol) -> World
end

class World
  def bar: () -> Hello
end
EOF

      manager.build do |env|
        walker = EnvironmentWalker.new(env: env).only_ancestors!

        walker.each_strongly_connected_component do |component|
          # pp component.map(&:to_s)
        end
      end
    end
  end

  def test_sort_nested_modules
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
module A::Foo
end

module A
  def hello: () -> Foo
end
EOF

      manager.build do |env|
        walker = EnvironmentWalker.new(env: env)

        components = walker.each_strongly_connected_component.to_a
        foo = components.find {|c| c.any? {|name| name.to_s == "::A::Foo" } }
        a = components.find {|c| c.any? {|name| name.to_s == "::A" } }

        # module A::Foo makes a dependency to A
        # A#hello makes a dependency to A::Foo
        assert_operator a.map(&:to_s), :==, foo.map(&:to_s)
      end
    end
  end

  def test_stdlib
    env = Environment.from_loader(EnvironmentLoader.new).resolve_type_names

    walker = EnvironmentWalker.new(env: env.resolve_type_names).only_ancestors!

    walker.each_strongly_connected_component do |component|
      # pp component.map(&:to_s)
    end
  end
end
