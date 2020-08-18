require "rbs"
require "rbs/test"
require "optparse"
require "shellwords"

include RBS::Test::SetupHelper

logger = Logger.new(STDERR)

begin
  opts = Shellwords.shellsplit(ENV["RBS_TEST_OPT"] || "-I sig")
  filter = ENV.fetch('RBS_TEST_TARGET', "").split(',').map! { |e| e.strip }
  skips = (ENV['RBS_TEST_SKIP'] || '').split(',').map! { |e| e.strip }
  RBS.logger_level = (ENV["RBS_TEST_LOGLEVEL"] || "info")
  sample_size = get_sample_size(ENV['RBS_TEST_SAMPLE_SIZE'] || '')
  double_mode = ENV['RBS_TEST_DOUBLE_TYPE_CHECKER_MODE'] || 'none'
  double_suite = ENV['RBS_TEST_DOUBLE_SUITE']  || 'none'

rescue InvalidSampleSizeError => exception
  RBS.logger.error exception.message
  exit 1
end

if filter.empty?
  STDERR.puts "rbs/test/setup handles the following environment variables:"
  STDERR.puts "  [REQUIRED] RBS_TEST_TARGET: test target class name, `Foo::Bar,Foo::Baz` for each class or `Foo::*` for all classes under `Foo`"
  STDERR.puts "  [OPTIONAL] RBS_TEST_SKIP: skip testing classes"
  STDERR.puts "  [OPTIONAL] RBS_TEST_OPT: options for signatures (`-r` for libraries or `-I` for signatures)"
  STDERR.puts "  [OPTIONAL] RBS_TEST_LOGLEVEL: one of debug|info|warn|error|fatal (defaults to info)"
  STDERR.puts "  [OPTIONAL] RBS_TEST_SAMPLE_SIZE: sets the amount of values in a collection to be type-checked (Set to `ALL` to type check all the values)"
  STDERR.puts "  [OPTIONAL] RBS_TEST_DOUBLE_TYPE_CHECKER_MODE: strict checks every double, lax ignores doubles but prints a warning, and none ignores all doubles(strict | lax | none)"
  STDERR.puts "  [OPTIONAL] RBS_TEST_DOUBLE_SUITE: sets the double suite in use"
  exit 1
end

loader = RBS::EnvironmentLoader.new
OptionParser.new do |opts|
  opts.on("-r [LIB]") do |name| loader.add(library: name) end
  opts.on("-I [DIR]") do |dir| loader.add(path: Pathname(dir)) end
end.parse!(opts)

env = RBS::Environment.from_loader(loader).resolve_type_names

def match(filter, name)
  if filter.end_with?("*")
    size = filter.size
    name.start_with?(filter[0, size - 1]) || name == filter[0, size-3]
  else
    filter == name
  end
end

def to_absolute_typename(type_name)
  RBS::Factory.new().type_name(type_name).absolute!
end

tester = RBS::Test::Tester.new(env: env)

module_name = Module.instance_method(:name)

TracePoint.trace :end do |tp|
  class_name = module_name.bind(tp.self).call&.yield_self {|name| to_absolute_typename name }

  if class_name
    if filter.any? {|f| match(to_absolute_typename(f).to_s, class_name.to_s) } && skips.none? {|f| match(f, class_name.to_s) }
      if env.class_decls.key?(class_name)
        logger.info "Setting up hooks for #{class_name}"
        tester.install!(tp.self, sample_size: sample_size, double_mode: double_mode, double_suite: double_suite)
      end
    end
  end
end

at_exit do
  if $!.nil? || $!.is_a?(SystemExit) && $!.success?
    if tester.targets.empty?
      logger.debug { "No type checker was installed!" }
    end
  end
end
