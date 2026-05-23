require "file"
require "process"
require "./home.cr"
require "../models/logger.cr"

module PassiveRulesUpdater
  REPO_URL = "https://github.com/owasp-noir/noir-passive-rules.git"

  # Default location for the image-baked ruleset. Resolves via
  # `bundled_rules_path` so specs (and adventurous packagers) can
  # point at a different prefix with NOIR_BUNDLED_RULES_PATH.
  DEFAULT_BUNDLED_RULES_PATH = "/opt/noir/passive_rules"

  # Image-baked rules location. The official Docker image clones
  # `noir-passive-rules` at build time and drops the result here so
  # `noir scan -P` Just Works without network or git. Bare installs
  # (homebrew / snap / source) won't have this path — `user_rules_path`
  # wins on those.
  def self.bundled_rules_path : String
    ENV["NOIR_BUNDLED_RULES_PATH"]? || DEFAULT_BUNDLED_RULES_PATH
  end

  # The user-managed rules path: where `noir rules update` clones to,
  # where `noir rules path` reports, and the canonical writable
  # location an end-user owns. Kept out of `effective_rules_path` so
  # the CLI rules subcommand has a stable single answer.
  def self.user_rules_path : String
    File.join(get_home, "passive_rules")
  end

  # Where `noir scan -P` should actually read rules from. Preference
  # order: user-managed path (so user-added rules and `rules update`
  # both win) → bundled image path → user path (gives the clone
  # fallback in `initialize_rules` something concrete to populate).
  def self.effective_rules_path : String
    user = user_rules_path
    return user if Dir.exists?(user) && !Dir.empty?(user)
    return bundled_rules_path if Dir.exists?(bundled_rules_path) && !Dir.empty?(bundled_rules_path)
    user
  end

  # True when the image-baked ruleset is available and the user hasn't
  # provided their own. Callers use this to skip the git-clone fallback
  # (which costs network + a git binary the image doesn't ship).
  def self.bundled_rules_available? : Bool
    user = user_rules_path
    return false if Dir.exists?(user) && !Dir.empty?(user)
    Dir.exists?(bundled_rules_path) && !Dir.empty?(bundled_rules_path)
  end

  # Check if the passive rules directory is a git repository and needs updates
  def self.check_for_updates(logger : NoirLogger, auto_update : Bool = false) : Bool
    rules_path = user_rules_path

    # Image-baked install: the user-managed path is empty / missing
    # but /opt/noir/passive_rules has rules. There's nothing to fetch
    # from upstream because the bundled rules are pinned to the image
    # tag — users who want fresher rules switch image tags or run
    # `noir rules update` to materialise the user path.
    if !Dir.exists?(rules_path) || Dir.empty?(rules_path)
      if bundled_rules_available?
        logger.debug "Passive rules: image-baked ruleset in use; skipping upstream update check."
        return true
      end
    end

    # Return early if directory doesn't exist
    unless Dir.exists?(rules_path)
      logger.debug "Passive rules directory does not exist: #{rules_path}"
      return false
    end

    # Check if it's a git repository
    git_dir = File.join(rules_path, ".git")
    unless Dir.exists?(git_dir)
      logger.debug "Passive rules directory is not a git repository"
      return check_revision_file(rules_path, logger)
    end

    logger.debug "Checking for passive rules updates..."

    begin
      # Fetch latest updates from remote
      result = Process.run("git", args: ["fetch", "--quiet"], chdir: rules_path,
        output: Process::Redirect::Close, error: Process::Redirect::Close)

      unless result.success?
        logger.debug "Failed to fetch updates for passive rules"
        return false
      end

      # Check if local is behind remote
      output = IO::Memory.new
      result = Process.run("git", args: ["rev-list", "--count", "HEAD..origin/main"],
        chdir: rules_path, output: output, error: Process::Redirect::Close)

      if result.success?
        behind_count = output.to_s.strip.to_i? || 0

        if behind_count > 0
          if auto_update
            logger.info "Updating passive rules (#{behind_count} commits behind)..."
            if update_rules(rules_path, logger)
              logger.success "Passive rules updated successfully."
              true
            else
              logger.warning "Failed to update passive rules automatically."
              notify_user_update_available(behind_count, logger)
              false
            end
          else
            notify_user_update_available(behind_count, logger)
            false
          end
        else
          logger.debug "Passive rules are up to date"
          true
        end
      else
        logger.debug "Failed to check passive rules update status"
        false
      end
    rescue ex : Exception
      logger.debug "Error checking for passive rules updates: #{ex.message}"
      false
    end
  end

  # Update the passive rules repository
  private def self.update_rules(rules_path : String, logger : NoirLogger) : Bool
    result = Process.run("git", args: ["pull", "--quiet"], chdir: rules_path,
      output: Process::Redirect::Close, error: Process::Redirect::Close)
    result.success?
  rescue ex : Exception
    logger.debug "Error updating passive rules: #{ex.message}"
    false
  end

  # Fallback for installations where the rules directory was unpacked
  # without git metadata (e.g. tarball install). We can't compare
  # against the upstream main branch here, so the best we can do is
  # confirm a `.revision` marker file exists and assume the rules are
  # usable. Updates from this path require a manual re-install.
  private def self.check_revision_file(rules_path : String, logger : NoirLogger) : Bool
    revision_file = File.join(rules_path, ".revision")

    unless File.exists?(revision_file)
      logger.debug "No revision file found in passive rules directory"
      return false
    end

    true
  end

  # Notify user that updates are available
  private def self.notify_user_update_available(behind_count : Int32, logger : NoirLogger)
    logger.warning "Passive rules are #{behind_count} commits behind the latest version."
    logger.sub "├── Run 'git pull' in ~/.config/noir/passive_rules/ to update"
    logger.sub "├── Or use 'git clone #{REPO_URL} ~/.config/noir/passive_rules/' to get the latest rules"
    logger.sub "├── Or run 'noir -b . -P --passive-scan-auto-update' to auto-update on startup"
  end

  # Initialize passive rules if they don't exist
  def self.initialize_rules(logger : NoirLogger) : Bool
    rules_path = user_rules_path

    # Return true if directory already exists and is not empty
    if Dir.exists?(rules_path) && !Dir.empty?(rules_path)
      return true
    end

    # The Docker image bakes a rules snapshot at /opt/noir/passive_rules
    # so `noir scan -P` can run without git or network. When the user
    # path is empty but the bundled path has rules, treat init as
    # already-done — `effective_rules_path` will resolve to the bundle
    # at load time.
    if bundled_rules_available?
      logger.debug "Passive rules: using image-baked ruleset at #{bundled_rules_path}"
      return true
    end

    logger.info "Initializing passive rules directory..."

    begin
      # Create parent directory if it doesn't exist
      Dir.mkdir_p(File.dirname(rules_path))

      # Clone the repository
      result = Process.run("git", args: ["clone", "--quiet", REPO_URL, rules_path],
        output: Process::Redirect::Close, error: Process::Redirect::Close)

      if result.success?
        logger.success "Passive rules initialized successfully."
        true
      else
        logger.warning "Failed to clone passive rules repository."
        logger.sub "➔ You can manually clone it with: git clone #{REPO_URL} #{rules_path}"

        # Create empty directory as fallback
        Dir.mkdir_p(rules_path) unless Dir.exists?(rules_path)
        false
      end
    rescue ex : Exception
      logger.debug "Error initializing passive rules: #{ex.message}"

      # Create empty directory as fallback
      begin
        Dir.mkdir_p(rules_path) unless Dir.exists?(rules_path)
      rescue
        # Ignore errors creating fallback directory
      end

      false
    end
  end
end
