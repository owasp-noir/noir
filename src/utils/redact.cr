require "yaml"

# Masks credentials in option values before they reach a log line. `-d`
# dumps every option, and debug output is what users paste into issues.
module Noir::Redact
  MASK = "***"

  # Options whose whole value is a credential.
  SECRET_KEYS = %w[ai_key]

  # `name: value` / `name=value` lists that carry credentials (probe
  # headers, header/cookie pvalue rules): the name stays visible for
  # debugging, the value is hidden. Other pvalue rules are left alone —
  # their values are printed in the endpoint output anyway.
  private NAMED_VALUE_LIST = /\A(?:probe_header|set_pvalue_(?:header|cookie))\z/

  # A URL inside free text (an option dump renders lists as `["…"]`).
  private URL_IN_TEXT = %r{[a-z][a-z0-9+.\-]*://[^\s"',\]]+}i

  # Userinfo of a URL. Greedy up to the last `@` of the authority, so a raw
  # `@` inside the password is covered too.
  private USERINFO = %r{(?<=://)[^/?#\s]*@}

  # A query value; AI gateways take `?key=` / `?code=` credentials.
  private QUERY_VALUE = /(?<=[?&])([^=&#]*)=[^&#]*/

  # Path, query and fragment of a URL: where webhook tokens live
  # (Slack/Discord put the secret in the path).
  private URL_TAIL = %r{\A([a-z][a-z0-9+.\-]*://[^/?#]+)[/?#].+\z}i

  def self.option(key : String, value : YAML::Any) : String
    if SECRET_KEYS.includes?(key)
      return value.to_s.empty? ? "" : MASK
    end

    if key.matches?(NAMED_VALUE_LIST) && (list = value.as_a?)
      return list.map { |entry| named_value(entry.to_s) }.to_s
    end

    key == "export_webhook" ? webhook(value.to_s) : url(value.to_s)
  end

  # Mask userinfo and query values of every URL in `text`, keeping the
  # query parameter names.
  def self.url(text : String) : String
    text.gsub(URL_IN_TEXT) do |match|
      masked = match.sub(USERINFO, "#{MASK}@")
      if query = masked.index('?')
        masked = masked[0...query] + masked[query..].gsub(QUERY_VALUE, "\\1=#{MASK}")
      end
      masked
    end
  end

  # A webhook URL down to its origin.
  def self.webhook(text : String) : String
    url(text).sub(URL_TAIL, "\\1/#{MASK}")
  end

  # `Name: value` → `Name: ***`. Without a separator (a malformed
  # `--probe-header "Authorization Bearer xyz"`) everything after the first
  # word is hidden, and a lone word is hidden whole.
  def self.named_value(entry : String) : String
    if sep = entry.index(/[=:]/)
      "#{entry[0..sep]}#{" " if entry[sep + 1]? == ' '}#{MASK}"
    elsif space = entry.index(' ')
      "#{entry[0..space]}#{MASK}"
    else
      MASK
    end
  end
end
