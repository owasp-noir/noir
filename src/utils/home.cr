def get_home
  config_dir = ""

  if ENV.has_key? "NOIR_HOME"
    config_dir = ENV["NOIR_HOME"]
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
