require "../../spec_helper"
require "../../../src/techs/techs"

describe "--only-techs and --exclude-techs functionality" do
  # `NoirTechs.resolve_tech_list` is the production resolution these flags
  # share (`detector.cr` for --only-techs and -t, `cli/commands/scan.cr` for
  # --exclude-techs). These examples used to re-type its body inline, so they
  # asserted a copy of the logic and could not fail when the shipped code was
  # wrong — which it was, in two ways: --exclude-techs matched on a substring
  # of the canonical name, and neither it nor -t stripped list entries.
  describe "only_techs filtering logic" do
    # Tests for the filtering logic used by --only-techs option
    # The option filters detector_list to only include specified technologies

    it "filters with valid single tech" do
      only_techs_value = "rails"
      detector_names = ["ruby_rails", "ruby_sinatra", "python_flask"]

      only_techs_list = NoirTechs.resolve_tech_list(only_techs_value)

      filtered_detectors = detector_names.select do |detector_name|
        only_techs_list.includes?(detector_name)
      end

      only_techs_list.should eq(["ruby_rails"])
      filtered_detectors.should eq(["ruby_rails"])
    end

    it "filters with multiple valid techs (comma-separated)" do
      only_techs_value = "rails,flask,express"
      detector_names = ["ruby_rails", "ruby_sinatra", "python_flask", "js_express", "go_gin"]

      only_techs_list = NoirTechs.resolve_tech_list(only_techs_value)

      filtered_detectors = detector_names.select do |detector_name|
        only_techs_list.includes?(detector_name)
      end

      only_techs_list.should contain("ruby_rails")
      only_techs_list.should contain("python_flask")
      only_techs_list.should contain("js_express")
      filtered_detectors.size.should eq(3)
      filtered_detectors.should contain("ruby_rails")
      filtered_detectors.should contain("python_flask")
      filtered_detectors.should contain("js_express")
    end

    it "filters with similar tech names (handles different formats)" do
      # Test that similar names like "ruby-rails", "ruby_rails", "rails" all map to "ruby_rails"
      only_techs_value = "ruby-rails,python-flask"
      detector_names = ["ruby_rails", "python_flask", "go_gin"]

      only_techs_list = NoirTechs.resolve_tech_list(only_techs_value)

      filtered_detectors = detector_names.select do |detector_name|
        only_techs_list.includes?(detector_name)
      end

      only_techs_list.should eq(["ruby_rails", "python_flask"])
      filtered_detectors.should eq(["ruby_rails", "python_flask"])
    end

    it "returns empty list when all techs are invalid" do
      only_techs_value = "invalid_tech,nonexistent"

      only_techs_list = NoirTechs.resolve_tech_list(only_techs_value)

      # When all techs are invalid, only_techs_list should be empty
      only_techs_list.should be_empty
    end

    it "handles whitespace in tech names" do
      only_techs_value = " rails , flask , express "
      detector_names = ["ruby_rails", "python_flask", "js_express", "go_gin"]

      only_techs_list = NoirTechs.resolve_tech_list(only_techs_value)

      filtered_detectors = detector_names.select do |detector_name|
        only_techs_list.includes?(detector_name)
      end

      filtered_detectors.size.should eq(3)
      filtered_detectors.should contain("ruby_rails")
      filtered_detectors.should contain("python_flask")
      filtered_detectors.should contain("js_express")
    end

    it "handles mixed valid and invalid techs" do
      only_techs_value = "rails,invalid_tech,flask"
      detector_names = ["ruby_rails", "python_flask", "go_gin"]

      only_techs_list = NoirTechs.resolve_tech_list(only_techs_value)

      filtered_detectors = detector_names.select do |detector_name|
        only_techs_list.includes?(detector_name)
      end

      # Only valid techs should be in the list
      only_techs_list.size.should eq(2)
      only_techs_list.should contain("ruby_rails")
      only_techs_list.should contain("python_flask")
      filtered_detectors.size.should eq(2)
    end

    it "handles case insensitive tech names" do
      only_techs_value = "Rails,FLASK,Express"
      detector_names = ["ruby_rails", "python_flask", "js_express"]

      only_techs_list = NoirTechs.resolve_tech_list(only_techs_value)

      filtered_detectors = detector_names.select do |detector_name|
        only_techs_list.includes?(detector_name)
      end

      filtered_detectors.size.should eq(3)
    end
  end

  describe "exclude_techs filtering logic" do
    # Tests for the filtering logic used by --exclude-techs option
    # The option filters detected techs to exclude specified technologies

    it "excludes with valid single tech" do
      exclude_techs_value = "rails"
      detected_techs = ["ruby_rails", "python_flask", "go_gin"]

      exclude_techs = NoirTechs.resolve_tech_list(exclude_techs_value).to_set
      filtered_techs = detected_techs.reject { |tech| exclude_techs.includes?(tech) }

      filtered_techs.should eq(["python_flask", "go_gin"])
      filtered_techs.should_not contain("ruby_rails")
    end

    it "excludes with multiple valid techs (comma-separated)" do
      exclude_techs_value = "rails,flask"
      detected_techs = ["ruby_rails", "python_flask", "go_gin", "js_express"]

      exclude_techs = NoirTechs.resolve_tech_list(exclude_techs_value).to_set
      filtered_techs = detected_techs.reject { |tech| exclude_techs.includes?(tech) }

      filtered_techs.size.should eq(2)
      filtered_techs.should eq(["go_gin", "js_express"])
      filtered_techs.should_not contain("ruby_rails")
      filtered_techs.should_not contain("python_flask")
    end

    it "excludes with similar tech names" do
      # Test that similar names like "ruby-rails" also exclude "ruby_rails"
      exclude_techs_value = "ruby-rails,python-flask"
      detected_techs = ["ruby_rails", "python_flask", "go_gin"]

      exclude_techs = NoirTechs.resolve_tech_list(exclude_techs_value).to_set
      filtered_techs = detected_techs.reject { |tech| exclude_techs.includes?(tech) }

      filtered_techs.should eq(["go_gin"])
    end

    it "keeps all techs when exclude list is invalid" do
      exclude_techs_value = "invalid_tech"
      detected_techs = ["ruby_rails", "python_flask"]

      exclude_techs = NoirTechs.resolve_tech_list(exclude_techs_value).to_set
      filtered_techs = detected_techs.reject { |tech| exclude_techs.includes?(tech) }

      # Invalid techs don't match anything, so nothing is excluded
      filtered_techs.should eq(detected_techs)
    end

    it "handles empty exclude techs" do
      exclude_techs_value = ""
      detected_techs = ["ruby_rails", "python_flask"]

      exclude_techs = NoirTechs.resolve_tech_list(exclude_techs_value).to_set
      filtered_techs = detected_techs.reject { |tech| exclude_techs.includes?(tech) }

      # An empty value resolves to no tech names, so nothing is excluded
      filtered_techs.should eq(detected_techs)
    end

    it "handles mixed valid and invalid techs in exclude list" do
      exclude_techs_value = "rails,invalid_tech,flask"
      detected_techs = ["ruby_rails", "python_flask", "go_gin"]

      exclude_techs = NoirTechs.resolve_tech_list(exclude_techs_value).to_set
      filtered_techs = detected_techs.reject { |tech| exclude_techs.includes?(tech) }

      # Only valid techs in exclude list should be excluded
      filtered_techs.size.should eq(1)
      filtered_techs.should eq(["go_gin"])
    end

    it "handles case insensitive tech names in exclude list" do
      exclude_techs_value = "Rails,FLASK"
      detected_techs = ["ruby_rails", "python_flask", "go_gin"]

      exclude_techs = NoirTechs.resolve_tech_list(exclude_techs_value).to_set
      filtered_techs = detected_techs.reject { |tech| exclude_techs.includes?(tech) }

      filtered_techs.should eq(["go_gin"])
    end

    # `--exclude-techs go_httprouter` used to drop `go_http` too: the filter
    # asked `similar_to_tech(entry).includes?(tech)`, a substring test on the
    # canonical name. Every key that is a prefix of another was affected —
    # go_http/go_httprouter, zig_http/zig_httpz,
    # elixir_phoenix/elixir_phoenix_channel and, the one a user is most
    # likely to hit, python_django/python_django_ninja.
    it "excludes only the named tech, not techs whose name it starts with" do
      [
        {"go_httprouter", "go_http"},
        {"zig_httpz", "zig_http"},
        {"python_django_ninja", "python_django"},
        {"elixir_phoenix_channel", "elixir_phoenix"},
      ].each do |(excluded, kept)|
        exclude_techs = NoirTechs.resolve_tech_list(excluded).to_set
        [excluded, kept].reject { |tech| exclude_techs.includes?(tech) }.should eq([kept])
      end
    end

    # The list is comma-separated, and people put a space after a comma.
    # `--exclude-techs` and `-t` split without stripping, so every entry
    # after the first resolved to "" and was silently ignored — while the
    # CLI validator, which does strip, reported the value as perfectly good.
    it "ignores whitespace around comma-separated entries" do
      exclude_techs_value = "js_express, python_flask ,\tgo_gin"
      detected_techs = ["js_express", "python_flask", "go_gin", "ruby_rails"]

      exclude_techs = NoirTechs.resolve_tech_list(exclude_techs_value).to_set
      filtered_techs = detected_techs.reject { |tech| exclude_techs.includes?(tech) }

      filtered_techs.should eq(["ruby_rails"])
    end

    it "excludes all techs when all are in exclude list" do
      exclude_techs_value = "rails,flask,gin"
      detected_techs = ["ruby_rails", "python_flask", "go_gin"]

      exclude_techs = NoirTechs.resolve_tech_list(exclude_techs_value).to_set
      filtered_techs = detected_techs.reject { |tech| exclude_techs.includes?(tech) }

      filtered_techs.should be_empty
    end
  end

  describe "interaction between only_techs and exclude_techs" do
    it "only_techs is applied during detection, exclude_techs is applied after" do
      # only_techs filters which detectors run
      # exclude_techs filters the results after detection
      # They work at different stages, so both can be used together

      # only_techs filtering first (during detection)
      only_techs_value = "rails,flask,gin"
      all_detectors = ["ruby_rails", "python_flask", "go_gin", "js_express"]

      only_techs_list = NoirTechs.resolve_tech_list(only_techs_value)

      detected_techs = all_detectors.select do |detector_name|
        only_techs_list.includes?(detector_name)
      end

      # After detection, apply exclude_techs
      exclude_techs_value = "flask"
      exclude_techs = NoirTechs.resolve_tech_list(exclude_techs_value).to_set
      final_techs = detected_techs.reject { |tech| exclude_techs.includes?(tech) }

      # Only rails and gin should remain (flask excluded)
      final_techs.size.should eq(2)
      final_techs.should contain("ruby_rails")
      final_techs.should contain("go_gin")
      final_techs.should_not contain("python_flask")
    end
  end

  describe "similar_to_tech for various frameworks" do
    # Test that similar_to_tech correctly maps various tech names

    it "maps framework names to full tech names" do
      NoirTechs.similar_to_tech("rails").should eq("ruby_rails")
      NoirTechs.similar_to_tech("flask").should eq("python_flask")
      NoirTechs.similar_to_tech("express").should eq("js_express")
      NoirTechs.similar_to_tech("gin").should eq("go_gin")
      NoirTechs.similar_to_tech("spring").should eq("java_spring")
      NoirTechs.similar_to_tech("django").should eq("python_django")
      NoirTechs.similar_to_tech("fastapi").should eq("python_fastapi")
      NoirTechs.similar_to_tech("kemal").should eq("crystal_kemal")
    end

    it "maps language-framework format names" do
      NoirTechs.similar_to_tech("ruby-rails").should eq("ruby_rails")
      NoirTechs.similar_to_tech("python-flask").should eq("python_flask")
      NoirTechs.similar_to_tech("go-gin").should eq("go_gin")
      NoirTechs.similar_to_tech("crystal-kemal").should eq("crystal_kemal")
    end

    it "maps underscore format names" do
      NoirTechs.similar_to_tech("ruby_rails").should eq("ruby_rails")
      NoirTechs.similar_to_tech("python_flask").should eq("python_flask")
      NoirTechs.similar_to_tech("go_gin").should eq("go_gin")
    end

    it "accepts canonical tech keys for --only-techs" do
      NoirTechs.similar_to_tech("js_fastify").should eq("js_fastify")
      NoirTechs.similar_to_tech("js_express").should eq("js_express")
    end

    it "returns empty string for unknown techs" do
      NoirTechs.similar_to_tech("unknown_framework").should eq("")
      NoirTechs.similar_to_tech("nonexistent").should eq("")
    end
  end
end
