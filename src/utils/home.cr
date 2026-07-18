require "../cli/common"

def get_home
  # NOIR_HOME wins — but only when it's set to a real value. The previous
  # `ENV.has_key? "NOIR_HOME"` check was also true for an exported-but-empty
  # `NOIR_HOME=""` (a shell-script bug, an unfilled container env template),
  # which then resolved rules/config/cache to *relative* paths under the
  # current working directory: `File.join("", "passive_rules") == "passive_rules"`.
  # Treat an empty value the same as unset and fall back to the OS default.
  if noir_home = ENV["NOIR_HOME"]?.presence
    # Env vars set outside a shell (Docker `ENV`, systemd `Environment=`,
    # some .env loaders) never get the shell's tilde expansion, so a literal
    # "~/noir" would otherwise resolve to a bogus "./~/noir" under the cwd.
    # Expand a leading ~ here so the path lands where the user meant.
    return noir_home.starts_with?('~') ? File.expand_path(noir_home, home: true) : noir_home
  end

  # Fall back to the per-OS default config location. The base env var must
  # exist; hardened containers and some CI runners unset HOME/APPDATA, so
  # fail with a clean CLI error instead of an unhandled `Missing ENV key`
  # (KeyError) stack trace — matching how every other subcommand errors.
  {% if flag?(:windows) %}
    appdata = ENV["APPDATA"]?.presence ||
              Noir::CLI.die("Cannot locate the noir config directory: neither NOIR_HOME nor APPDATA is set. Set NOIR_HOME to a writable directory.")
    "#{appdata}\\noir"
  {% else %}
    home = ENV["HOME"]?.presence ||
           Noir::CLI.die("Cannot locate the noir config directory: neither NOIR_HOME nor HOME is set. Set NOIR_HOME to a writable directory.")
    "#{home}/.config/noir"
  {% end %}
end
