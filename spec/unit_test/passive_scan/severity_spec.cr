require "../../spec_helper"
require "../../../src/passive_scan/severity.cr"

describe PassiveScanSeverity do
  describe ".meets_threshold?" do
    it "allows critical severity with critical threshold" do
      PassiveScanSeverity.meets_threshold?("critical", "critical").should be_true
    end

    it "allows critical severity with high threshold" do
      PassiveScanSeverity.meets_threshold?("critical", "high").should be_true
    end

    it "allows critical severity with medium threshold" do
      PassiveScanSeverity.meets_threshold?("critical", "medium").should be_true
    end

    it "allows critical severity with low threshold" do
      PassiveScanSeverity.meets_threshold?("critical", "low").should be_true
    end

    it "denies high severity with critical threshold" do
      PassiveScanSeverity.meets_threshold?("high", "critical").should be_false
    end

    it "allows high severity with high threshold" do
      PassiveScanSeverity.meets_threshold?("high", "high").should be_true
    end

    it "allows high severity with medium threshold" do
      PassiveScanSeverity.meets_threshold?("high", "medium").should be_true
    end

    it "allows high severity with low threshold" do
      PassiveScanSeverity.meets_threshold?("high", "low").should be_true
    end

    it "denies medium severity with critical threshold" do
      PassiveScanSeverity.meets_threshold?("medium", "critical").should be_false
    end

    it "denies medium severity with high threshold" do
      PassiveScanSeverity.meets_threshold?("medium", "high").should be_false
    end

    it "allows medium severity with medium threshold" do
      PassiveScanSeverity.meets_threshold?("medium", "medium").should be_true
    end

    it "allows medium severity with low threshold" do
      PassiveScanSeverity.meets_threshold?("medium", "low").should be_true
    end

    it "denies low severity with critical threshold" do
      PassiveScanSeverity.meets_threshold?("low", "critical").should be_false
    end

    it "denies low severity with high threshold" do
      PassiveScanSeverity.meets_threshold?("low", "high").should be_false
    end

    it "denies low severity with medium threshold" do
      PassiveScanSeverity.meets_threshold?("low", "medium").should be_false
    end

    it "allows low severity with low threshold" do
      PassiveScanSeverity.meets_threshold?("low", "low").should be_true
    end

    it "handles case-insensitive input" do
      PassiveScanSeverity.meets_threshold?("CRITICAL", "high").should be_true
      PassiveScanSeverity.meets_threshold?("High", "HIGH").should be_true
      PassiveScanSeverity.meets_threshold?("Medium", "LOW").should be_true
    end

    it "defaults to true for unknown severity levels" do
      PassiveScanSeverity.meets_threshold?("unknown", "high").should be_true
      PassiveScanSeverity.meets_threshold?("high", "unknown").should be_true
      PassiveScanSeverity.meets_threshold?("unknown", "unknown").should be_true
    end
  end

  describe ".get_level" do
    it "returns correct numeric levels" do
      PassiveScanSeverity.get_level("critical").should eq(4)
      PassiveScanSeverity.get_level("high").should eq(3)
      PassiveScanSeverity.get_level("medium").should eq(2)
      PassiveScanSeverity.get_level("low").should eq(1)
    end

    it "returns 0 for unknown severity" do
      PassiveScanSeverity.get_level("unknown").should eq(0)
    end

    it "handles case-insensitive input" do
      PassiveScanSeverity.get_level("CRITICAL").should eq(4)
      PassiveScanSeverity.get_level("High").should eq(3)
    end
  end

  describe ".valid?" do
    it "returns true for valid severity levels" do
      PassiveScanSeverity.valid?("critical").should be_true
      PassiveScanSeverity.valid?("high").should be_true
      PassiveScanSeverity.valid?("medium").should be_true
      PassiveScanSeverity.valid?("low").should be_true
    end

    it "returns false for invalid severity levels" do
      PassiveScanSeverity.valid?("invalid").should be_false
      PassiveScanSeverity.valid?("").should be_false
      PassiveScanSeverity.valid?("moderate").should be_false
    end

    it "handles case-insensitive input" do
      PassiveScanSeverity.valid?("CRITICAL").should be_true
      PassiveScanSeverity.valid?("High").should be_true
    end
  end

  describe ".valid_levels" do
    it "returns all valid severity levels" do
      levels = PassiveScanSeverity.valid_levels
      levels.should contain("critical")
      levels.should contain("high")
      levels.should contain("medium")
      levels.should contain("low")
      levels.size.should eq(4)
    end
  end
end