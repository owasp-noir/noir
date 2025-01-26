require "../../src/completions"

describe "Completion Script Generation" do
  it "has a generate_zsh_completion_script method" do
    generate_zsh_completion_script.size.should be > 0
  end

  it "has a generate_bash_completion_script method" do
    generate_bash_completion_script.size.should be > 0
  end

  it "has a generate_fish_completion_script method" do
    generate_fish_completion_script.size.should be > 0
  end
end
