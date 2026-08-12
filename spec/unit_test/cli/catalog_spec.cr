require "../../spec_helper"
require "../../../src/cli/catalog"
require "../../../src/cli/scan_flags"
require "../../../src/cli/router"
require "../../../src/completions"

# The catalog is the single source for the `noir` command surface. These
# examples guard the two things a single source can still get wrong: an entry
# that nothing downstream implements, and a downstream consumer that quietly
# stopped reading it.
describe Noir::CLI::Catalog do
  it "names every command exactly once" do
    names = Noir::CLI::Catalog::NAMES
    names.should_not be_empty
    names.uniq.size.should eq(names.size)
  end

  it "gives every command a summary and an argument shape" do
    Noir::CLI::Catalog::COMMANDS.each do |command|
      command.summary.should_not be_empty
      command.usage_args.should_not be_empty
    end
  end

  it "routes every catalog command to a help page" do
    Noir::CLI::Catalog::NAMES.each do |name|
      Noir::CLI::HelpCommand.route_for([name]).should_not eq(Noir::CLI::HelpCommand::Route::Unknown)
    end
  end

  it "is what the router dispatches on" do
    Noir::CLI::KNOWN_COMMANDS.should eq(Noir::CLI::Catalog::NAMES)
  end

  it "offers every command in every shell completion" do
    scripts = [
      Noir::Completions::Zsh.script,
      Noir::Completions::Bash.script,
      Noir::Completions::Fish.script,
      Noir::Completions::Elvish.script,
    ]
    Noir::CLI::Catalog::COMMANDS.each do |command|
      scripts.each(&.should(contain(command.name)))
    end
  end

  it "offers every sub-action in every shell completion" do
    scripts = [
      Noir::Completions::Zsh.script,
      Noir::Completions::Bash.script,
      Noir::Completions::Fish.script,
      Noir::Completions::Elvish.script,
    ]
    Noir::CLI::Catalog.completable.each do |(name, values)|
      next if values.empty?
      # `help` completes the verb list, which zsh offers through its
      # described `commands` array rather than as a plain word list; the
      # example above already covers those names.
      next if name == "help"
      scripts.each(&.should(contain(values.join(" "))))
    end
  end
end

describe Noir::CLI::ScanFlags do
  it "spells every flag exactly once" do
    names = Noir::CLI::ScanFlags::NAMES
    names.uniq.size.should eq(names.size)
  end

  it "uses long forms with a `--` prefix and short forms with one dash" do
    Noir::CLI::ScanFlags::FLAGS.each do |flag|
      flag.long.should start_with("--")
      flag.description.should_not be_empty
      flag.shorts.each do |short|
        short.should start_with("-")
        short.should_not start_with("--")
      end
    end
  end

  it "gives every choice-valued flag something to offer" do
    Noir::CLI::ScanFlags.with_choices.each do |flag|
      flag.choices.should_not be_empty
    end
  end

  it "completes every flag in every shell" do
    long_form_scripts = [
      Noir::Completions::Zsh.script,
      Noir::Completions::Bash.script,
      Noir::Completions::Elvish.script,
    ]
    # Fish registers long flags as `-l name`, without the leading dashes.
    fish = Noir::Completions::Fish.script

    Noir::CLI::ScanFlags::FLAGS.each do |flag|
      long_form_scripts.each(&.should(contain(flag.long)))
      fish.should contain("-l #{flag.long.lchop("--")}")
    end
  end
end
