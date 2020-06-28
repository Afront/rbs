require "rbs"
require "pp"

module RBS
  module Test
    module Hook
      def self.alias_names(target)
        aliased_target, punctuation = target.to_s.sub(/([?!=])$/, ''), $1

        [
          "#{aliased_target}__with__#{Test.suffix}#{punctuation}",
          "#{aliased_target}__without__#{Test.suffix}#{punctuation}"
        ]
      end

      def self.setup_alias_method_chain(klass, target)
        with_method, without_method = alias_names(target)

        klass.instance_eval do
          alias_method without_method, target
          alias_method target, with_method

          case
          when public_method_defined?(without_method)
            public target
          when protected_method_defined?(without_method)
            protected target
          when private_method_defined?(without_method)
            private target
          end
        end
      end

      def self.hook_method_source(method_name, key)
        with_name, without_name = alias_names(method_name)

        <<RUBY
def #{with_name}(*args)
  begin
    return_from_call = false
    block_calls = []

    if block_given?
      result = #{without_name}(*args) do |*block_args|
        return_from_block = false

        begin
          block_result = yield(*block_args)
          return_from_block = true
        ensure
          exn = $!

          case
          when return_from_block
            # Returned from yield
            block_calls << ::RBS::Test::ArgumentsReturn.return(
              arguments: block_args,
              value: block_result
            )
          when exn
            # Exception
            block_calls << ::RBS::Test::ArgumentsReturn.exception(
              arguments: block_args,
              exception: exn
            )
          else
            # break?
            block_calls << ::RBS::Test::ArgumentsReturn.break(
              arguments: block_args
            )
          end
        end

        block_result
      end
    else
      result = #{without_name}(*args)
    end
    return_from_call = true
    result
  ensure
    exn = $!

    case
    when return_from_call
      method_call = ::RBS::Test::ArgumentsReturn.return(
        arguments: args,
        value: result
      )
    when exn
      method_call = ::RBS::Test::ArgumentsReturn.exception(
        arguments: args,
        exception: exn
      )
    else
      method_call = ::RBS::Test::ArgumentsReturn.break(arguments: args)
    end

    trace = ::RBS::Test::CallTrace.new(
      method_name: #{method_name.inspect},
      method_call: method_call,
      block_calls: block_calls,
      block_given: block_given?,
    )

    ::RBS::Test::Observer.notify(#{key.inspect}, self, trace)
  end

  result
end

ruby2_keywords :#{with_name}
RUBY
      end

      def self.hook_instance_method(klass, method, key:)
        source = hook_method_source(method, key)

        klass.module_eval(source)
        setup_alias_method_chain klass, method
      end

      def self.hook_singleton_method(klass, method, key:)
        source = hook_method_source(method, key)

        klass.singleton_class.module_eval(source)
        setup_alias_method_chain klass.singleton_class, method
      end

      def self.setup_instance_type_check(klass, definition, builder:)
        key = "#{definition.type_name}__#{SecureRandom.hex(10)}"

        checker = TypeChecker.new(self_class: klass, definition: definition, builder: definition_builder)
        Observer.register(key, checker)

        definition.methods.each do |method_name, method|
          if method.implemented_in == definition.type_name
            self.hook_instance_method(klass, method_name, key: key)
          end
        end
      end
    end

    class TypeChecker
      class Error < Exception
        attr_reader :errors

        def initialize(errors)
          @errors = errors
          super "Type error detected: [#{errors.map {|e| Errors.to_string(e) }.join(", ")}]"
        end
      end

      attr_reader :self_class, :definition, :definition_builder

      def initialize(self_class:, definition:, builder:)
        @self_class = self_class
        @definition = definition
        @builder = builder
      end

      def call(obj, trace)
        method_name = trace.method_name
        check = TypeCheck.new(self_class: self_class, builder: builder)

        method_types = definition.methods[method_name].method_types

        errors = method_types.map do |method_type|
          errors = check.method_call(method_name, method_type, trace, errors: [])
          break if errors.empty?
          errors
        end

        if errors
          raise Error.new(errors.last)
        end
      end
    end
  end
end
