# The aggregator declares the global prefix + path version and mounts the
# sub-APIs. Those routes live in other files and never name `Grape::API`,
# so the `/api/v1` prefix must be propagated through the mount graph.
module MyAPI
  class Root < ::MyAPI::Base
    prefix :api
    version 'v1', using: :path

    # A nested helper class that is NOT a Grape API. It must not steal the
    # prefix/version/mount declarations that belong to Root.
    class Error < StandardError
    end

    mount ::MyAPI::Users
    mount ::MyAPI::Widgets
  end
end
