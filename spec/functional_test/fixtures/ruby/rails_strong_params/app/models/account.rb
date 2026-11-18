class Account < ApplicationRecord
  devise :database_authenticatable, :recoverable
end
