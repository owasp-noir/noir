module Types
  module UserQueries
    extend ActiveSupport::Concern

    included do
      field :current_user, Types::UserType, null: true
    end
  end
end
