require "file"
require "process"
require "./home.cr"
require "../models/logger.cr"

module PassiveRulesUpdater
  REPO_URL = "https://github.com/owasp-noir/noir-passive-rules.git"

  # Check if the passive rules directory is a git repository and needs updates
  def self.check_for_updates(logger : NoirLogger, auto_update : Bool = false) : Bool
    rules_path = File.join(get_home, "passive_rules")

    # Return early if directory doesn't exist
    unless Dir.exists?(rules_path)
      logger.debug "Passive rules directory does not exist: #{rules_path}"
      return false
    end

    # Check if it's a git repository
    git_dir = File.join(rules_path, ".git")
    unless Dir.exists?(git_dir)
      logger.debug "Passive rules directory is not a git repository"
      return check_revision_file(rules_path, logger, auto_update)
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

  # Check for updates using a revision file (fallback method)
  private def self.check_revision_file(rules_path : String, logger : NoirLogger, auto_update : Bool) : Bool
    revision_file = File.join(rules_path, ".revision")

    unless File.exists?(revision_file)
      logger.debug "No revision file found in passive rules directory"
      return false
    end

    # For now, we'll just assume rules are up to date if revision file exists
    # A more sophisticated implementation could fetch the latest revision from GitHub API
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
    rules_path = File.join(get_home, "passive_rules")

    # Return true if directory already exists and is not empty
    if Dir.exists?(rules_path) && !Dir.empty?(rules_path)
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
