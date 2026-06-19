class SpecOnlyAPI < Grape::API
  get "/spec-only" do
    "not production"
  end
end
