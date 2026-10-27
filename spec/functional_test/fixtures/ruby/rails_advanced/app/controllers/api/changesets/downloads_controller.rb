module Api
  module Changesets
    class DownloadsController < ApplicationController
      def show
        accept = request.headers["HTTP_ACCEPT"]
        langs = http_accept_language.user_preferred_languages
      end
    end
  end
end
