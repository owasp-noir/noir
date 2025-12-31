require "../../spec_helper"
require "../../../src/techs/techs"

describe "--only-techs and --exclude-techs functionality" do
  describe "only_techs filtering logic" do
    # Tests for the filtering logic used by --only-techs option
    # The option filters detector_list to only include specified technologies

    it "filters with valid single tech" do
      # Simulate the only_techs filtering logic from detector.cr
      only_techs_value = "rails"
      detector_names = ["ruby_rails", "ruby_sinatra", "python_flask"]

      only_techs_list = only_techs_value.split(",").map do |tech|
        NoirTechs.similar_to_tech(tech.strip)
      end.reject(&.empty?)

      filtered_detectors = detector_names.select do |detector_name|
        only_techs_list.includes?(detector_name)
      end

      only_techs_list.should eq(["ruby_rails"])
      filtered_detectors.should eq(["ruby_rails"])
    end

    it "filters with multiple valid techs (comma-separated)" do
      only_techs_value = "rails,flask,express"
      detector_names = ["ruby_rails", "ruby_sinatra", "python_flask", "js_express", "go_gin"]

      only_techs_list = only_techs_value.split(",").map do |tech|
        NoirTechs.similar_to_tech(tech.strip)
      end.reject(&.empty?)

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

      only_techs_list = only_techs_value.split(",").map do |tech|
        NoirTechs.similar_to_tech(tech.strip)
      end.reject(&.empty?)

      filtered_detectors = detector_names.select do |detector_name|
        only_techs_list.includes?(detector_name)
      end

      only_techs_list.should eq(["ruby_rails", "python_flask"])
      filtered_detectors.should eq(["ruby_rails", "python_flask"])
    end

    it "returns empty list when all techs are invalid" do
      only_techs_value = "invalid_tech,nonexistent"

      only_techs_list = only_techs_value.split(",").map do |tech|
        NoirTechs.similar_to_tech(tech.strip)
      end.reject(&.empty?)

      # When all techs are invalid, only_techs_list should be empty
      only_techs_list.should be_empty
    end

    it "handles whitespace in tech names" do
      only_techs_value = " rails , flask , express "
      detector_names = ["ruby_rails", "python_flask", "js_express", "go_gin"]

      only_techs_list = only_techs_value.split(",").map do |tech|
        NoirTechs.similar_to_tech(tech.strip)
      end.reject(&.empty?)

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

      only_techs_list = only_techs_value.split(",").map do |tech|
        NoirTechs.similar_to_tech(tech.strip)
      end.reject(&.empty?)

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

      only_techs_list = only_techs_value.split(",").map do |tech|
        NoirTechs.similar_to_tech(tech.strip)
      end.reject(&.empty?)

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
      # Simulate the exclude_techs filtering logic from noir.cr
      exclude_techs_value = "rails"
      detected_techs = ["ruby_rails", "python_flask", "go_gin"]

      exclude_techs = exclude_techs_value.split(",")
      filtered_techs = detected_techs.reject do |tech|
        exclude_techs.any? { |exclude_tech| NoirTechs.similar_to_tech(exclude_tech).includes?(tech) }
      end

      filtered_techs.should eq(["python_flask", "go_gin"])
      filtered_techs.should_not contain("ruby_rails")
    end

    it "excludes with multiple valid techs (comma-separated)" do
      exclude_techs_value = "rails,flask"
      detected_techs = ["ruby_rails", "python_flask", "go_gin", "js_express"]

      exclude_techs = exclude_techs_value.split(",")
      filtered_techs = detected_techs.reject do |tech|
        exclude_techs.any? { |exclude_tech| NoirTechs.similar_to_tech(exclude_tech).includes?(tech) }
      end

      filtered_techs.size.should eq(2)
      filtered_techs.should eq(["go_gin", "js_express"])
      filtered_techs.should_not contain("ruby_rails")
      filtered_techs.should_not contain("python_flask")
    end

    it "excludes with similar tech names" do
      # Test that similar names like "ruby-rails" also exclude "ruby_rails"
      exclude_techs_value = "ruby-rails,python-flask"
      detected_techs = ["ruby_rails", "python_flask", "go_gin"]

      exclude_techs = exclude_techs_value.split(",")
      filtered_techs = detected_techs.reject do |tech|
        exclude_techs.any? { |exclude_tech| NoirTechs.similar_to_tech(exclude_tech).includes?(tech) }
      end

      filtered_techs.should eq(["go_gin"])
    end

    it "keeps all techs when exclude list is invalid" do
      exclude_techs_value = "invalid_tech"
      detected_techs = ["ruby_rails", "python_flask"]

      exclude_techs = exclude_techs_value.split(",")
      filtered_techs = detected_techs.reject do |tech|
        exclude_techs.any? { |exclude_tech| NoirTechs.similar_to_tech(exclude_tech).includes?(tech) }
      end

      # Invalid techs don't match anything, so nothing is excluded
      filtered_techs.should eq(detected_techs)
    end

    it "handles empty exclude techs" do
      exclude_techs_value = ""
      detected_techs = ["ruby_rails", "python_flask"]

      exclude_techs = exclude_techs_value.split(",")
      filtered_techs = detected_techs.reject do |tech|
        exclude_techs.any? { |exclude_tech| NoirTechs.similar_to_tech(exclude_tech).includes?(tech) }
      end

      # Empty string split results in [""], which doesn't match any valid tech
      filtered_techs.should eq(detected_techs)
    end

    it "handles mixed valid and invalid techs in exclude list" do
      exclude_techs_value = "rails,invalid_tech,flask"
      detected_techs = ["ruby_rails", "python_flask", "go_gin"]

      exclude_techs = exclude_techs_value.split(",")
      filtered_techs = detected_techs.reject do |tech|
        exclude_techs.any? { |exclude_tech| NoirTechs.similar_to_tech(exclude_tech).includes?(tech) }
      end

      # Only valid techs in exclude list should be excluded
      filtered_techs.size.should eq(1)
      filtered_techs.should eq(["go_gin"])
    end

    it "handles case insensitive tech names in exclude list" do
      exclude_techs_value = "Rails,FLASK"
      detected_techs = ["ruby_rails", "python_flask", "go_gin"]

      exclude_techs = exclude_techs_value.split(",")
      filtered_techs = detected_techs.reject do |tech|
        exclude_techs.any? { |exclude_tech| NoirTechs.similar_to_tech(exclude_tech).includes?(tech) }
      end

      filtered_techs.should eq(["go_gin"])
    end

    it "excludes all techs when all are in exclude list" do
      exclude_techs_value = "rails,flask,gin"
      detected_techs = ["ruby_rails", "python_flask", "go_gin"]

      exclude_techs = exclude_techs_value.split(",")
      filtered_techs = detected_techs.reject do |tech|
        exclude_techs.any? { |exclude_tech| NoirTechs.similar_to_tech(exclude_tech).includes?(tech) }
      end

      filtered_techs.should be_empty
    end
  end

  describe "interaction between only_techs and exclude_techs" do
    it "only_techs is applied during detection, exclude_techs is applied after" do
      # only_techs filters which detectors run
      # exclude_techs filters the results after detection
      # They work at different stages, so both can be used together

      # Simulate only_techs filtering first (during detection)
      only_techs_value = "rails,flask,gin"
      all_detectors = ["ruby_rails", "python_flask", "go_gin", "js_express"]

      only_techs_list = only_techs_value.split(",").map do |tech|
        NoirTechs.similar_to_tech(tech.strip)
      end.reject(&.empty?)

      detected_techs = all_detectors.select do |detector_name|
        only_techs_list.includes?(detector_name)
      end

      # After detection, apply exclude_techs
      exclude_techs_value = "flask"
      exclude_techs = exclude_techs_value.split(",")
      final_techs = detected_techs.reject do |tech|
        exclude_techs.any? { |exclude_tech| NoirTechs.similar_to_tech(exclude_tech).includes?(tech) }
      end

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

    it "returns empty string for unknown techs" do
      NoirTechs.similar_to_tech("unknown_framework").should eq("")
      NoirTechs.similar_to_tech("nonexistent").should eq("")
    end
  end
end
