require "test_helper"

require "rbs/test"
require "logger"

return unless Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.7.0')

class RBS::Test::TypeCheckTest < Minitest::Test
  include TestHelper
  include RBS

  def test_type_check
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
class Array[Elem]
end

type foo = String | Integer | [String, String] | ::Array[Integer]

module M
  type t = Integer
  type s = t
end

interface _ToInt
  def to_int: () -> Integer
end
EOF
      manager.build do |env|
        typecheck = Test::TypeCheck.new(
          self_class: Integer,
          builder: DefinitionBuilder.new(env: env),
          sampling: false
        )

        assert typecheck.value(3, parse_type("::foo"))
        assert typecheck.value("3", parse_type("::foo"))
        assert typecheck.value(["foo", "bar"], parse_type("::foo"))
        assert typecheck.value([1, 2, 3], parse_type("::foo"))
        refute typecheck.value(:foo, parse_type("::foo"))
        refute typecheck.value(["foo", 3], parse_type("::foo"))
        refute typecheck.value([1, 2, "3"], parse_type("::foo"))

        assert typecheck.value(Object, parse_type("singleton(::Object)"))
        assert typecheck.value(Object, parse_type("::Class"))
        refute typecheck.value(Object, parse_type("singleton(::String)"))

        assert typecheck.value(3, parse_type("::M::t"))
        assert typecheck.value(3, parse_type("::M::s"))

        assert typecheck.value(3, parse_type("::_ToInt"))
        refute typecheck.value("3", parse_type("::_ToInt"))

        assert typecheck.value([1,2,3].each, parse_type("Enumerator[Integer, Array[Integer]]"))
        assert typecheck.value(loop, parse_type("Enumerator[nil, bot]"))
      end
    end
  end

  def test_type_check_array_sampling
    SignatureManager.new do |manager|
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)

        typecheck = Test::TypeCheck.new(self_class: Integer, builder: builder, sampling: true)

        assert typecheck.value([], parse_type("::Array[::Integer]"))
        assert typecheck.value([1], parse_type("::Array[::Integer]"))
        refute typecheck.value([1,2,3] + ["a"], parse_type("::Array[::Integer]"))

        assert typecheck.value(Array.new(500, 1), parse_type("::Array[::Integer]"))
        refute typecheck.value(Array.new(99, 1) + Array.new(401, "a"), parse_type("::Array[::Integer]"))
      end
    end
  end

  def test_type_check_hash_sampling
    SignatureManager.new do |manager|
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)

        typecheck = Test::TypeCheck.new(self_class: Integer, builder: builder, sampling: true)

        # hash = Array.new(100) {|i| [i, i.to_s] }.to_h

        assert typecheck.value({}, parse_type("::Hash[::Integer, ::String]"))
        assert typecheck.value(Array.new(100) {|i| [i, i.to_s] }.to_h, parse_type("::Hash[::Integer, ::String]"))
        
        assert typecheck.value(Array.new(1000) {|i| [i, i.to_s] }.to_h, parse_type("::Hash[::Integer, ::String]"))
        refute typecheck.value(
          Array.new(99) {|i| [i, i.to_s] }.to_h.merge({ foo: 'bar', bar: 'baz', baz: 'foo' }),
          parse_type("::Hash[::Integer, ::String]")
        )
        refute typecheck.value(
          Array.new(99) {|i| [i, i.to_s] }.to_h.merge({ 1001 => :bar, 1002 => :baz, 1003 => :foo }),
          parse_type("::Hash[::Integer, ::String]")
        )
      end
    end
  end

  def test_type_check_enumerator_sampling
    SignatureManager.new do |manager|
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)

        typecheck = Test::TypeCheck.new(self_class: Integer, builder: builder, sampling: true)

        assert typecheck.value([1,2,3].each, parse_type("Enumerator[Integer, Array[Integer]]"))
        assert typecheck.value(Array.new(400, 3).each, parse_type("Enumerator[Integer, Array[Integer]]"))

        refute typecheck.value((Array.new(99, 1) + Array.new(401, "a")).each, parse_type("Enumerator[Integer, Array[Integer]]"))

        assert typecheck.value(loop, parse_type("Enumerator[nil, bot]"))
      end
    end
  end

  def test_sampling_handling
    SignatureManager.new do |manager|
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)

        no_sampling_check = Test::TypeCheck.new(self_class: Integer, builder: builder, sampling: false)
        assert_equal [1,2,3,4], no_sampling_check.sample([1,2,3,4])
        Array.new(400) {|i| i.to_s }.tap do |a|
          assert_equal a, no_sampling_check.sample(a)
        end

        sampling_check = Test::TypeCheck.new(self_class: Integer, builder: builder, sampling: true)
        assert_equal [1,2,3,4], sampling_check.sample([1,2,3,4])
        Array.new(400) {|i| i.to_s }.tap do |a|
          refute_equal a, sampling_check.sample(a)
          assert_equal 100, sampling_check.sample(a).size
          assert_empty (sampling_check.sample(a) - a)
        end
      end
    end
  end

  def do_sample_size_test(type_check, env_string, expected)
    silence_warnings do
      sample_size = type_check.get_sample_size
      ENV['RBS_TEST_SAMPLE_SIZE'] = env_string

      refute_equal type_check.get_sample_size, nil
      assert_instance_of Integer, sample_size
      assert_equal type_check.get_sample_size, expected
    end
  end

  def test_sample_size_getter
    SignatureManager.new do |manager|
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)
        sampling_check = Test::TypeCheck.new(self_class: Integer, builder: builder, sampling: true)
    
        do_sample_size_test(sampling_check, '100', 100)
        do_sample_size_test(sampling_check, '1000', 1000)
        do_sample_size_test(sampling_check, '10.5', 11)
        do_sample_size_test(sampling_check, '-10.5', Test::TypeCheck::DEFAULT_SAMPLE_SIZE)
        do_sample_size_test(sampling_check, '-1000', Test::TypeCheck::DEFAULT_SAMPLE_SIZE)
        do_sample_size_test(sampling_check, '-100', Test::TypeCheck::DEFAULT_SAMPLE_SIZE)
        do_sample_size_test(sampling_check, 'foo', Test::TypeCheck::DEFAULT_SAMPLE_SIZE)
        do_sample_size_test(sampling_check, nil, Test::TypeCheck::DEFAULT_SAMPLE_SIZE)
      end
    end
  end

  def test_typecheck_return
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
type foo = String | Integer
EOF
      manager.build do |env|
        typecheck = Test::TypeCheck.new(
          self_class: Object,
          builder: DefinitionBuilder.new(env: env),
          sampling: false
        )

        parse_method_type("(Integer) -> String").tap do |method_type|
          errors = []
          typecheck.return "#foo",
                           method_type,
                           method_type.type,
                           Test::ArgumentsReturn.exception(arguments: [1], exception: RuntimeError.new("test")),
                           errors,
                           return_error: Test::Errors::ReturnTypeError
          assert_empty errors

          errors.clear
          typecheck.return "#foo",
                           method_type,
                           method_type.type,
                           Test::ArgumentsReturn.return(arguments: [1], value: "5"),
                           errors,
                           return_error: Test::Errors::ReturnTypeError
          assert_empty errors
        end

        parse_method_type("(Integer) -> bot").tap do |method_type|
          errors = []
          typecheck.return "#foo",
                           method_type,
                           method_type.type,
                           Test::ArgumentsReturn.exception(arguments: [1], exception: RuntimeError.new("test")),
                           errors,
                           return_error: Test::Errors::ReturnTypeError
          assert_empty errors

          errors.clear
          typecheck.return "#foo",
                           method_type,
                           method_type.type,
                           Test::ArgumentsReturn.return(arguments: [1], value: "5"),
                           errors,
                           return_error: Test::Errors::ReturnTypeError
          assert errors.any? {|error| error.is_a?(Test::Errors::ReturnTypeError) }
        end
      end
    end
  end

  def test_typecheck_args
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
type foo = String | Integer
EOF
      manager.build do |env|
        typecheck = Test::TypeCheck.new(
          self_class: Object,
          builder: DefinitionBuilder.new(env: env),
          sampling: false
        )

        parse_method_type("(Integer) -> String").tap do |method_type|
          errors = []
          typecheck.args "#foo",
                         method_type,
                         method_type.type,
                         Test::ArgumentsReturn.return(arguments: [1], value: "1"),
                         errors,
                         type_error: Test::Errors::ArgumentTypeError,
                         argument_error: Test::Errors::ArgumentError
          assert_empty errors

          errors = []
          typecheck.args "#foo",
                         method_type,
                         method_type.type,
                         Test::ArgumentsReturn.return(arguments: ["1"], value: "1"),
                         errors,
                         type_error: Test::Errors::ArgumentTypeError,
                         argument_error: Test::Errors::ArgumentError
          assert errors.any? {|error| error.is_a?(Test::Errors::ArgumentTypeError) }

          errors = []
          typecheck.args "#foo",
                         method_type,
                         method_type.type,
                         Test::ArgumentsReturn.return(arguments: [1, 2], value: "1"),
                         errors,
                         type_error: Test::Errors::ArgumentTypeError,
                         argument_error: Test::Errors::ArgumentError
          assert errors.any? {|error| error.is_a?(Test::Errors::ArgumentError) }

          errors = []
          typecheck.args "#foo",
                         method_type,
                         method_type.type,
                         Test::ArgumentsReturn.return(arguments: [{ hello: :world }], value: "1"),
                         errors,
                         type_error: Test::Errors::ArgumentTypeError,
                         argument_error: Test::Errors::ArgumentError
          assert errors.any? {|error| error.is_a?(Test::Errors::ArgumentTypeError) }
        end

        parse_method_type("(foo: Integer, ?bar: String, **Symbol) -> String").tap do |method_type|
          errors = []
          typecheck.args "#foo",
                         method_type,
                         method_type.type,
                         Test::ArgumentsReturn.return(arguments: [{ foo: 31, baz: :baz }], value: "1"),
                         errors,
                         type_error: Test::Errors::ArgumentTypeError,
                         argument_error: Test::Errors::ArgumentError
          assert_empty errors

          errors = []
          typecheck.args "#foo",
                         method_type,
                         method_type.type,
                         Test::ArgumentsReturn.return(arguments: [{ foo: "foo" }], value: "1"),
                         errors,
                         type_error: Test::Errors::ArgumentTypeError,
                         argument_error: Test::Errors::ArgumentError
          assert errors.any? {|error| error.is_a?(Test::Errors::ArgumentTypeError) }

          errors = []
          typecheck.args "#foo",
                         method_type,
                         method_type.type,
                         Test::ArgumentsReturn.return(arguments: [{ bar: "bar" }], value: "1"),
                         errors,
                         type_error: Test::Errors::ArgumentTypeError,
                         argument_error: Test::Errors::ArgumentError
          assert errors.any? {|error| error.is_a?(Test::Errors::ArgumentError) }
        end

        parse_method_type("(?String, ?encoding: String) -> String").tap do |method_type|
          errors = []
          typecheck.args "#foo",
                         method_type,
                         method_type.type,
                         Test::ArgumentsReturn.return(arguments: [{ encoding: "ASCII-8BIT" }], value: "foo"),
                         errors,
                         type_error: Test::Errors::ArgumentTypeError,
                         argument_error: Test::Errors::ArgumentError
          assert_empty errors
        end

        parse_method_type("(parent: untyped, type: untyped) -> untyped").tap do |method_type|
          errors = []
          typecheck.args "#foo",
                         method_type,
                         method_type.type,
                         Test::ArgumentsReturn.return(arguments: [{ parent: nil, type: nil }], value: nil),
                         errors,
                         type_error: Test::Errors::ArgumentTypeError,
                         argument_error: Test::Errors::ArgumentError
          assert_empty errors.map {|e| Test::Errors.to_string(e) }
        end

        parse_method_type("(Integer?, *String) -> String").tap do |method_type|
          errors = []
          typecheck.args "#foo",
                         method_type,
                         method_type.type,
                         Test::ArgumentsReturn.return(arguments: [1], value: "1"),
                         errors,
                         type_error: Test::Errors::ArgumentTypeError,
                         argument_error: Test::Errors::ArgumentError
          assert_empty errors

          typecheck.args "#foo",
                         method_type,
                         method_type.type,
                         Test::ArgumentsReturn.return(arguments: [1, ''], value: "1"),
                         errors,
                         type_error: Test::Errors::ArgumentTypeError,
                         argument_error: Test::Errors::ArgumentError
          assert_empty errors

          typecheck.args "#foo",
                         method_type,
                         method_type.type,
                         Test::ArgumentsReturn.return(arguments: [1, '', ''], value: "1"),
                         errors,
                         type_error: Test::Errors::ArgumentTypeError,
                         argument_error: Test::Errors::ArgumentError
          assert_empty errors
        end
      end
    end
  end

  def test_type_overload
    SignatureManager.new do |manager|
      manager.files[Pathname("foo.rbs")] = <<EOF
class Foo
  def foo: () -> String
         | (Integer) -> String

  def bar: () -> String
end
EOF
      manager.build do |env|
        builder = DefinitionBuilder.new(env: env)

        typecheck = Test::TypeCheck.new(self_class: Object, builder: builder, sampling: false)

        builder.build_instance(type_name("::Foo")).tap do |foo|
          typecheck.overloaded_call(
            foo.methods[:foo],
            "#foo",
            Test::CallTrace.new(
              method_name: :foo,
              method_call: Test::ArgumentsReturn.return(
                arguments: [],
                value: "foo"
              ),
              block_calls: [],
              block_given: false
            ),
            errors: []
          ).tap do |errors|
            assert_empty errors
          end

          typecheck.overloaded_call(
            foo.methods[:bar],
            "#bar",
            Test::CallTrace.new(
              method_name: :bar,
              method_call: Test::ArgumentsReturn.return(
                arguments: [],
                value: 30
              ),
              block_calls: [],
              block_given: false
            ),
            errors: []
          ).tap do |errors|
            assert_equal 1, errors.size
            assert_instance_of RBS::Test::Errors::ReturnTypeError, errors[0]
          end

          typecheck.overloaded_call(
            foo.methods[:foo],
            "#foo",
            Test::CallTrace.new(
              method_name: :foo,
              method_call: Test::ArgumentsReturn.return(
                arguments: [3],
                value: 30
              ),
              block_calls: [],
              block_given: false
            ),
            errors: []
          ).tap do |errors|
            assert_equal 1, errors.size
            assert_instance_of RBS::Test::Errors::UnresolvedOverloadingError, errors[0]
          end
        end
      end
    end
  end
end
