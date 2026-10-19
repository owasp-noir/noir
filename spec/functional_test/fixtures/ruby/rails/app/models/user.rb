class User < ApplicationRecord
  # Declared over two lines, as `rails generate devise` writes it. No
  # :confirmable / :lockable, so no confirmation or unlock routes.
  devise :database_authenticatable, :registerable,
         :recoverable, :trackable, :validatable
end
