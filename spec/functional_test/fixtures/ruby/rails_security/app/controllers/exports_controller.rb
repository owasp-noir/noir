class ExportsController < ApplicationController
  rate_limit to: 5, within: 1.minute,
             only: %i[create]

  def show
  end

  def create
  end
end
