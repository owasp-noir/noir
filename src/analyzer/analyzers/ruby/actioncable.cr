require "../../../models/analyzer"
require "../../engines/ruby_engine"

module Analyzer::Ruby
  # Surfaces Rails Action Cable real-time attack surface as `ws://`
  # endpoints. An `ApplicationCable::Channel` subclass exposes public
  # methods the client invokes as actions (`perform("speak", ...)`) over
  # the cable connection; `mount ActionCable.server => "/cable"` mounts the
  # connection in `config/routes.rb`. Each callable action becomes one
  # endpoint `ws://<mount>/<Channel>/<action>` (bare
  # `ws://<mount>/<Channel>` when a channel has no actions), method "SEND",
  # protocol "ws" — so the existing WebsocketTagger tags them.
  #
  # Line-scan analyzer (Ruby house style). The cable mount lives in
  # `routes.rb` while channels live under `app/channels/`, so the mount is
  # collected across every `.rb` file first, then joined onto the channels.
  class ActionCable < RubyEngine
    # `class ChatChannel < ApplicationCable::Channel` (or the framework base
    # `ActionCable::Channel::Base`). The base module `class
    # ApplicationCable::Channel < ...` carries a `::` in the subclass name,
    # so `(\w+)` never matches it — the base definition is skipped.
    CHANNEL_CLASS = /^\s*class\s+(\w+)\s*<\s*(?:ApplicationCable::Channel|ActionCable::Channel::Base)\b/

    # `mount ActionCable.server => "/cable"`.
    CABLE_MOUNT = /\bmount\s+ActionCable\.server\s*=>\s*["']([^"']+)["']/

    # An instance method definition (Ruby CLI house-style regex).
    DEF_RE = /^\s*def\s+([a-z_]\w*[?!]?)\s*(?:[(\s]|$)/

    # Action Cable lifecycle callbacks — never client-invokable actions.
    NON_ACTION_METHODS = Set{"subscribed", "unsubscribed", "initialize"}

    # The generated `ApplicationCable::Channel` base (`class Channel <
    # ActionCable::Channel::Base`) matches CHANNEL_CLASS but is the shared
    # base, not a real channel. Real channels follow the `<Feature>Channel`
    # convention, so the bare name "Channel" is the base to skip.
    NON_CHANNEL_NAMES = Set{"Channel"}

    # Rails' default Action Cable mount path when routes.rb does not mount
    # it explicitly (a standalone cable server still serves `/cable`).
    DEFAULT_MOUNT = "cable"

    def analyze
      mount = nil.as(String?)
      channels = [] of ChannelInfo

      base_paths.each do |current_base_path|
        get_files_by_extension(".rb").each do |path|
          next unless path_under_root?(path, current_base_path)
          next if RubyEngine.ruby_test_path?(path)

          begin
            content = read_file_content(path)

            if mount.nil? && (m = content.match(CABLE_MOUNT))
              mount = m[1].strip.lstrip('/')
            end

            collect_channels(content, path, channels) if content.includes?("Channel")
          rescue e
            logger.debug "Error analyzing #{path}: #{e}"
            next
          end
        end
      end

      # Also pick up the mount from `.ru`/routes files scanned above; fall
      # back to the framework default when a channel exists but no explicit
      # mount was found.
      surface_prefix = (mount || DEFAULT_MOUNT)
      emit(channels, surface_prefix)
      @result
    end

    private record ChannelInfo,
      name : String,
      actions : Array(Tuple(String, Int32)),
      path : String,
      line : Int32

    private def collect_channels(content : String, path : String, channels : Array(ChannelInfo))
      lines = content.lines
      lines.each_with_index do |line, index|
        m = line.match(CHANNEL_CLASS)
        next unless m

        name = m[1]
        next if NON_CHANNEL_NAMES.includes?(name)
        actions = extract_actions(lines, index)
        channels << ChannelInfo.new(name, actions, path, index + 1)
      end
    end

    # Collects the public, non-lifecycle method names declared in the
    # channel class body starting at `class_line`, bounded by the matching
    # `end` at the class's indentation. Methods below a bare `private` /
    # `protected` are helpers, not actions.
    private def extract_actions(lines : Array(String), class_line : Int32) : Array(Tuple(String, Int32))
      actions = [] of Tuple(String, Int32)
      seen = Set(String).new

      class_indent = lines[class_line][/\A\s*/].size
      is_private = false

      idx = class_line + 1
      while idx < lines.size
        line = lines[idx]
        stripped = line.strip

        # Close the class body at the `end` that returns to the class's
        # own indentation.
        if stripped == "end" && line[/\A\s*/].size <= class_indent
          break
        end

        if stripped == "private" || stripped == "protected"
          is_private = true
        elsif stripped == "public"
          is_private = false
        elsif !is_private && (m = line.match(DEF_RE))
          action = m[1]
          unless NON_ACTION_METHODS.includes?(action) || seen.includes?(action)
            seen << action
            actions << {action, idx + 1}
          end
        end

        idx += 1
      end

      actions
    end

    private def emit(channels : Array(ChannelInfo), surface_prefix : String)
      channels.each do |channel|
        base = surface_prefix.empty? ? channel.name : "#{surface_prefix}/#{channel.name}"

        if channel.actions.empty?
          @result << build_endpoint("ws://#{base}", channel.path, channel.line)
          next
        end

        channel.actions.each do |action, line|
          @result << build_endpoint("ws://#{base}/#{action}", channel.path, line)
        end
      end
    end

    private def build_endpoint(url : String, path : String, line : Int32) : Endpoint
      ep = Endpoint.new(url, "SEND", Details.new(PathInfo.new(path, line)))
      ep.protocol = "ws"
      ep
    end
  end
end
