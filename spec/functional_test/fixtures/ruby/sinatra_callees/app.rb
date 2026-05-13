require 'sinatra'

get '/users' do
  page = params['page']
  users = UserService.list(page)
  users.each do |user| AuditLog.write(user)
  end
  json serialize_users(users)
end

post '/users' do
  payload = JSON.parse(request.body.read)
  user = UserService.create(payload)
  redirect_to user_url(user)
end

get '/ping' do; head :ok; end

get '/ready' do
  status = if Health.ready?
    Health.check
  else
    Health.down
  end
  json status_payload(status)
end
