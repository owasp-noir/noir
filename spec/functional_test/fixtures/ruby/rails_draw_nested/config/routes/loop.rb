get "/once", to: "loops#once"
scope :again do
  draw :loop
end
