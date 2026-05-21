scope path: "drawn" do
  get "health",
      to: "monitor#ping"
end
