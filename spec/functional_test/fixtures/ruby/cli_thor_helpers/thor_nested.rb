require "thor"

class Deploy < Thor
  # Nested exception classes subclass Thor::Error, not Thor::Group: they say
  # nothing about the commands declared around them.
  class Error < Thor::Error; end

  class Rollback < Thor::Error
  end

  desc "plan", "Plan the deploy"
  def plan
    puts "plan"
  end

  desc "apply", "Apply the plan"
  def apply
    puts "apply"
  end

  # A nested Thor::Group holds generator steps only; its `end` hands the
  # class body back to the commands that follow.
  class Steps < Thor::Group
    desc "Runs the steps"

    def prepare_it
      puts "prepare"
    end
  end

  desc "verify", "Verify the deploy"
  def verify
    puts "verify"
  end

  desc "finish", "Finish the deploy"
  def finish
    puts "finish"
  end
end

Deploy.start(ARGV)
