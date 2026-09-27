module Noir
  # `--fail-on`: which kinds of diff-mode findings make the scan exit non-zero,
  # so a CI job can block a pull request on them.
  module DiffGate
    extend self

    # Exit status when a gate fires. 1 is a usage error and 2 is `--strict`'s
    # "the scan itself was incomplete"; a CI step has to be able to tell the
    # three apart.
    EXIT_CODE = 3

    CATEGORIES = %w[added removed changed auth-removed]

    def parse(value : String) : Array(String)
      value.split(',').map(&.strip.downcase).reject(&.empty?).uniq!
    end

    def unknown(categories : Array(String)) : Array(String)
      categories.reject { |category| CATEGORIES.includes?(category) }
    end

    # `auth-removed` is read off the `auth` tag, and tags exist only when a
    # tagger ran. Without one the gate could never fire, which in CI looks
    # exactly like a pull request that removed no auth.
    def needs_taggers?(categories : Array(String)) : Bool
      categories.includes?("auth-removed")
    end

    # The categories that fired, given how many findings each one has.
    def fired(categories : Array(String), counts : Hash(String, Int32)) : Array(String)
      categories.select { |category| counts.fetch(category, 0) > 0 }
    end
  end
end
