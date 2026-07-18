def get_home
  config_dir = ""

  if ENV.has_key? "NOIR_HOME"
    config_dir = ENV["NOIR_HOME"]
    # Env vars set outside a shell (Docker `ENV`, systemd `Environment=`,
    # some .env loaders) never get the shell's tilde expansion, so a
    # literal "~/noir" would otherwise resolve to a bogus "./~/noir"
    # under the cwd. Expand a leading ~ here so the path lands where the
    # user meant.
    config_dir = File.expand_path(config_dir, home: true) if config_dir.starts_with?('~')
  else
    # Define the config directory and file based on the OS
    {% if flag?(:windows) %}
      config_dir = "#{ENV["APPDATA"]}\\noir"
    {% else %}
      config_dir = "#{ENV["HOME"]}/.config/noir"
    {% end %}
  end

  config_dir
end
