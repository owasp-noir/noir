class Posts::Show < BrowserAction
  # Inferred as `GET /posts/:post_id` (the `:post_id` from the singularized
  # resource name).
  action do
    json PostQuery.new.find(id)
  end
end
