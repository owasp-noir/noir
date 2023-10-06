require "./logger"

class Deliver
  @logger : NoirLogger
  @options : Hash(Symbol, String)
  @is_debug : Bool
  @is_color : Bool
  @is_log : Bool
  @proxy : String
  @headers : Hash(String, String) = {} of String => String

  def initialize(options : Hash(Symbol, String))
    @options = options
    @is_debug = str_to_bool(options[:debug])
    @is_color = str_to_bool(options[:color])
    @is_log = str_to_bool(options[:nolog])
    @proxy = options[:send_proxy]
    @logger = NoirLogger.new @is_debug, @is_color, @is_log

    if options[:send_with_headers] != ""
      headers_tmp = options[:send_with_headers].split("::NOIR::HEADERS::SPLIT::")
      @logger.system "Setting headers from command line."
      headers_tmp.each do |header|
        if header.includes? ":"
          @logger.debug "Adding '#{header}' to headers."
          splited = header.split(":")
          @headers[splited[0]] = splited[1].gsub(/\s/, "")
        end
      end
      @logger.info_sub "#{@headers.size} headers added."
    end
  end

  def proxy
    @proxy
  end

  def run
    # After inheriting the class, write an action code here.
  end
end
