require "./logger"

class Analyzer
  @result : Array(Endpoint)
  @base_path : String
  @url : String
  @scope : String
  @logger : NoirLogger

  def initialize(options : Hash(Symbol, String))
    @base_path = options[:base]
    @url = options[:url]
    @result = [] of Endpoint
    @scope = options[:scope]
    @logger = NoirLogger.new
  end

  def run
    # After inheriting the class, write an action code here.
  end

  macro define_getter_methods(names)
    {% for name, index in names %}
      def {{name.id}}
        @{{name.id}}
      end
    {% end %}
  end

  define_getter_methods [result, base_path, url, scope, logger]
end
