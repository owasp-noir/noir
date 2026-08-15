module Routes::Misc
  def self.home(env)
    payload = HomeService.build
    env.redirect "/dashboard"
  end

  def self.create_user(env)
    data = env.params.json["user"]
    UserService.create(data)
  end

  def self.search(env)
    q = env.params.json["q"]?
    SearchService.run(q)
  end
end
