# Helpers shared by the four completion-script generators.
module Noir::Completions
  # Wraps `value` in a single-quoted shell literal, closing and reopening the
  # quote around any `'` it contains. zsh, bash and fish all read `'\''` as
  # an embedded quote, so one form covers every script we emit — which
  # matters because the strings being quoted are command summaries and flag
  # descriptions written by contributors, not constants chosen for this.
  def self.quote(value : String) : String
    "'#{value.gsub("'", %q('\''))}'"
  end
end
