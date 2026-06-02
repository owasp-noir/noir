class Posts::Show < BrowserAction
  # `route do` is the other spelling of Lucky's inference macro. Inferred as
  # `GET /posts/:post_id` (the `:post_id` from the singularized resource).
  route do
    json PostQuery.new.find(id)
  end
end
