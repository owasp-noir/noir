module Routes::API::Items
  def self.show(env)
    id = env.params.url["id"]
    ItemLookup.find(id)
  end
end
