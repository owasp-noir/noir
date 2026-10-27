module Api
  module Changesets
    class DownloadsController < ApplicationController
      def show
        accept = request.headers["HTTP_ACCEPT"]
        langs = http_accept_language.user_preferred_languages
        version = request.headers["HTTP_VERSION"]
        type = request.headers["CONTENT_TYPE"]
      end
    end
  end
end
