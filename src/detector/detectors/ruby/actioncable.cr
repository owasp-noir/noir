require "../../../models/detector"

module Detector::Ruby
  # Detects Rails Action Cable: an `ApplicationCable::Channel` /
  # `ActionCable::Channel::Base` subclass, the `ActionCable::Connection::Base`
  # connection, or a `mount ActionCable.server` route. Gates the Action Cable
  # analyzer, which emits channel actions as `ws://` realtime endpoints.
  class ActionCable < Detector
    detector_for "ruby_actioncable", extensions: %w[.rb .ru]

    ACTIONCABLE_MARKER = /<\s*ApplicationCable::Channel\b|<\s*ActionCable::Channel::Base\b|<\s*ActionCable::Connection::Base\b|\bmount\s+ActionCable\.server\b/

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".rb") || filename.ends_with?(".ru")
      content_matches?(file_contents, ACTIONCABLE_MARKER)
    end
  end
end
