class User < ApplicationRecord
  # Declared over lines, as `rails generate devise` writes it. No
  # :confirmable / :lockable, so no confirmation or unlock routes;
  # :omniauthable adds an authorization and a callback route for each provider.
  devise :database_authenticatable, :registerable,
         :recoverable, :trackable, :validatable,
         :omniauthable, omniauth_providers: %i[github gitlab]
end
