require "../../../models/detector"

module Detector::Ruby
  # Detects Rails Action Cable: an `ApplicationCable::Channel` /
  # `ActionCable::Channel::Base` subclass, the `ActionCable::Connection::Base`
  # connection, or a `mount ActionCable.server` route. Gates the Action Cable
  # analyzer, which emits channel actions as `ws://` realtime endpoints.
  class ActionCable < Detector
    ACTIONCABLE_MARKER = /<\s*ApplicationCable::Channel\b|<\s*ActionCable::Channel::Base\b|<\s*ActionCable::Connection::Base\b|\bmount\s+ActionCable\.server\b/

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".rb") || filename.ends_with?(".ru")
      file_contents.matches?(ACTIONCABLE_MARKER)
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".rb") || filename.ends_with?(".ru")
    end

    def set_name
      @name = "ruby_actioncable"
    end
  end
end
