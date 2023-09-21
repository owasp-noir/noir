class ZAP
  @endpoint : String
  @apikey : String

  API_ACCESS = "/JSON/core/action/accessUrl"

  def initialize(@endpoint)
    if ENV.keys.includes? "ZAP_API_KEY"
      @apikey = ENV["ZAP_API_KEY"].to_s
    else
      @apikey = ""
    end
  end

  def add_url(url : String)
    call(@endpoint + API_ACCESS + "?url=#{url}")
  end

  def call(query : String)
    if @apikey == ""
      HTTP::Client.get(query)
    else
      HTTP::Client.get(query, headers: {"X-ZAP-API-Key" => @apikey})
    end
  end
end
