Rails.application.configure do
  config.base = '/prodbase'
  config.cond = '/c2' if ENV['X']
end
