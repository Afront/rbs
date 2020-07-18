module RBS
  module Test
    module SetupHelper
      class InvalidSampleSizeError < StandardError
        attr_reader :string
        
        def initialize(string)
          @string = string
          super("Sample size should be a positive integer: `#{string}`")
        end
      end
      
      DEFAULT_SAMPLE_SIZE = 100
      
      def get_sample_size(string)
        case string
        when nil
          DEFAULT_SAMPLE_SIZE
        when 'ALL'
          nil
        else
          raise InvalidSampleSizeError.new(string) unless string.to_i.positive?
          string.to_i
        end
      end
    end
  end
end