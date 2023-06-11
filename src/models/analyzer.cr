class Analyzer
  @result : Array(Endpoint)
  @base_path : String
  @url : String

  def initialize(options : Hash(Symbol, String))
    @base_path = options[:base]
    @url = options[:url]
  end

  def run
    # After inheriting the class, write an action code here.
  end

  def result
    @result
  end
end
