Rails.application.routes.draw do
  # Doorkeeper's OAuth2 provider routes. `controllers` remaps the
  # token endpoints onto the app's own controller (so params/callees
  # resolve), and `skip_controllers` drops the management UIs — the
  # generated route set must honor both.
  use_doorkeeper do
    controllers tokens: 'oauth/tokens'
    skip_controllers :applications, :authorized_applications
  end
end
