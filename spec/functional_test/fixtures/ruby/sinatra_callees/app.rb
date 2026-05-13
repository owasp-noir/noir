require 'sinatra'

get '/users' do
  page = params['page']
  users = UserService.list(page)
  AuditLog.write('list')
  json serialize_users(users)
end

post '/users' do
  payload = JSON.parse(request.body.read)
  user = UserService.create(payload)
  redirect_to user_url(user)
end

get '/ping' do; head :ok; end

get '/ready' do
  if Health.ready?
    json status_payload(Health.check)
  end
end
