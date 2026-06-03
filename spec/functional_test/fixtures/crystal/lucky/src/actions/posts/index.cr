class Posts::Index < BrowserAction
  # `action do` has no path: Lucky infers `GET /posts` from the class name.
  action do
    json PostQuery.new
  end
end
