class NoirRunner
  @options : Hash(Symbol, String)

  def initialize(options)
    @options = options
  end

  def options
    @options
  end

  def run
    puts @options[:format]
  end
end
