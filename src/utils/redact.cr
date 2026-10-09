require "yaml"

# Masks credentials in option values before they reach a log line. `-d`
# dumps every option, and debug output is what users paste into issues.
module Noir::Redact
  MASK = "***"

  # Options whose whole value is a credential.
  SECRET_KEYS = %w[ai_key]

  # `name: value` / `name=value` lists (probe headers, pvalue rules): the
  # name stays visible for debugging, the value is hidden.
  private NAMED_VALUE_LIST = /\A(?:probe_header|set_pvalue(?:_\w+)?)\z/

  # Userinfo in any URL. Greedy up to the last `@` of the authority, so a
  # raw `@` inside the password is covered too.
  private USERINFO = %r{(?<=://)[^/?#\s]*@}

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

  # Strip userinfo from every URL in `text`.
  def self.url(text : String) : String
    text.gsub(USERINFO, "#{MASK}@")
  end

  # A webhook URL down to its origin.
  def self.webhook(text : String) : String
    url(text).sub(URL_TAIL, "\\1/#{MASK}")
  end

  private def self.named_value(entry : String) : String
    (sep = entry.index(/[=:]/)) ? "#{entry[0..sep]}#{MASK}" : MASK
  end
end
