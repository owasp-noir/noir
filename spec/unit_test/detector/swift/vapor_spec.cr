require "../../../spec_helper"
require "../../../../src/detector/detectors/swift/*"

describe "Detect Swift Vapor" do
  options = create_test_options
  instance = Detector::Swift::Vapor.new options

  it "detects the Vapor framework dependency" do
    package = <<-SWIFT
      dependencies: [
          .package(url: "https://github.com/vapor/vapor.git", from: "4.89.0"),
      ]
      SWIFT
    instance.detect("Package.swift", package).should be_true
  end

  it "detects a Vapor product reference" do
    package = <<-SWIFT
      dependencies: [ .package(url: "https://github.com/example/web.git", from: "1.0.0") ]
      .product(name: "Vapor", package: "vapor")
      SWIFT
    instance.detect("Package.swift", package).should be_true
  end

  it "does not treat vapor-org ecosystem packages as Vapor" do
    # Hummingbird apps routinely depend on these; matching the bare
    # "vapor" substring used to tag them as Vapor and emit phantom routes.
    package = <<-SWIFT
      dependencies: [
          .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
          .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.7.0"),
          .package(url: "https://github.com/vapor/jwt-kit.git", from: "5.0.0"),
      ]
      SWIFT
    instance.detect("Package.swift", package).should be_false
  end

  it "only applies to Package.swift manifests" do
    instance.applicable?("Package.swift").should be_true
    instance.applicable?("Sources/App/routes.swift").should be_false
  end
end

describe "Detect Swift Hummingbird" do
  options = create_test_options
  instance = Detector::Swift::Hummingbird.new options

  it "detects the Hummingbird framework dependency" do
    package = <<-SWIFT
      dependencies: [
          .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
      ]
      SWIFT
    instance.detect("Package.swift", package).should be_true
  end

  it "only applies to Package.swift manifests" do
    instance.applicable?("Package.swift").should be_true
    instance.applicable?("Sources/App/App.swift").should be_false
  end
end

describe "Detect Swift Kitura" do
  options = create_test_options
  instance = Detector::Swift::Kitura.new options

  it "detects the Kitura framework dependency" do
    package = <<-SWIFT
      dependencies: [
          .package(url: "https://github.com/Kitura/Kitura.git", from: "2.9.0"),
      ]
      SWIFT
    instance.detect("Package.swift", package).should be_true
  end

  it "only applies to Package.swift manifests" do
    instance.applicable?("Package.swift").should be_true
    instance.applicable?("Sources/App/main.swift").should be_false
  end
end
