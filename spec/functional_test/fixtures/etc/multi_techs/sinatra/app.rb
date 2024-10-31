require 'sinatra'

get '/' do
  puts param['query']
end

post "/update" do
  puts "update"
end