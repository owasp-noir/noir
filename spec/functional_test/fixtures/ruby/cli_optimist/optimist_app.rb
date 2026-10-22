require 'optimist'

opts = Optimist::options do
  opt :name, "Your name", type: :string
  opt :verbose, "Verbose mode"
end

api_key = ENV["OPTIMIST_API_KEY"]
puts opts[:name], api_key
