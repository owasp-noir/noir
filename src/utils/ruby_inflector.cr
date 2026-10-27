module Noir
  # The common subset of ActiveSupport's singular rules, applied to the
  # word's tail as Rails does (`scheduled_statuses` -> `scheduled_status`).
  # Shared by the Rails analyzer (nested route keys such as `:status_id`)
  # and the auth tagger (the model CanCanCan derives from a controller
  # name), so both have to agree with Rails.
  # ponytail: no `-ves`/`-oes`/`-ices` rules and a short irregular list;
  # add one when a name comes out wrong.
  module RubyInflector
    SINGULAR_IRREGULARS = {"people" => "person", "men" => "man", "children" => "child"}

    def self.singularize(name : String) : String
      return name if name.matches?(/(?:\A|_)(?:news|series|species|information|equipment|money|rice|fish|sheep|jeans|police)\z/)
      SINGULAR_IRREGULARS.each { |plural, single| return name.rchop(plural) + single if name.ends_with?(plural) }
      return name.rchop("zes") if name.ends_with?("zzes")
      return name.rchop("es") if name.matches?(/(?:alias|status|bus|ss|x|ch|sh)es\z/)
      return "#{name.rchop("ies")}y" if name.matches?(/(?:[^aeiouy]|qu)ies\z/)
      return "#{name.rchop('a')}um" if name.matches?(/[ti]a\z/)
      return name.rchop('s') if name.ends_with?('s') && !name.ends_with?("ss") && name.size > 1
      name
    end
  end
end
