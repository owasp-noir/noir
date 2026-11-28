Rails.application.routes.draw do
  draw :admin
  draw "public/pages"
  scope :loop do
    draw :loop
  end
end
