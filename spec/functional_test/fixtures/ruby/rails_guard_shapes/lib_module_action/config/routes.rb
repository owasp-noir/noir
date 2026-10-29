Rails.application.routes.draw do
  post "uploads" => "uploads#create"
  post "uploads/create-multipart" => "uploads#create_multipart"
end
