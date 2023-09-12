require "./logger"

class Detector
  @logger : NoirLogger
  @is_debug : Bool
  @is_color : Bool
  @is_log : Bool
  @name : String
  @base_path : String

  def initialize(options : Hash(Symbol, String))
    @is_debug = str_to_bool(options[:debug])
    @is_color = str_to_bool(options[:color])
    @is_log = str_to_bool(options[:nolog])
    @name = ""
    @base_path = options[:base]

    @logger = NoirLogger.new @is_debug, @is_color, @is_log
  end

  def detect(filename : String, file_contents : String) : Bool
    # After inheriting the class, write an action code here.
    false
  end

  def get_parent_path(path : String) : String
    path.split("/")[0..-2].join("/")
  end

  def set_base_path(check : Bool, custom_base : String)
    if check
      locator = CodeLocator.instance

      if custom_base != ""
        locator.set("#{@name}_basepath", custom_base)
      else
        locator.set("#{@name}_basepath", @base_path)
      end
    end
  end

  macro define_getter_methods(names)
    {% for name, index in names %}
      def {{name.id}}
        @{{name.id}}
      end
    {% end %}
  end

  define_getter_methods [name, logger]
end
