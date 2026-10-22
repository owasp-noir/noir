require 'sinatra'

get '/real' do
  HELP = <<~TXT
    get '/in-heredoc' do
  TXT
  HELP
end

=begin
get '/dead' do
  'old'
end
=end

post '/after-comment' do
  'ok'
end

__END__
get '/afterend' do
end
