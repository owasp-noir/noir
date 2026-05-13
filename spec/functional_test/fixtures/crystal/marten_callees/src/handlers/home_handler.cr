module Placeholder; end

class PlaceholderHandler; end

class HomeHandler < Marten::Handler
  def get
    payload = HomeService.build
    message = HomePresenter.render(payload)
    respond message
  end
end
