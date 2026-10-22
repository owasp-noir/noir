class User < ApplicationRecord
  # Declared over lines, as `rails generate devise` writes it. No
  # :confirmable / :lockable, so no confirmation or unlock routes;
  # :omniauthable adds the /auth/:provider and /auth/:provider/callback routes.
  devise :database_authenticatable, :registerable,
         :recoverable, :trackable, :validatable,
         :omniauthable, omniauth_providers: %i[github]
end
