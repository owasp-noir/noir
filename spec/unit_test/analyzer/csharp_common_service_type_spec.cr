require "../../spec_helper"
require "../../../src/analyzer/analyzers/csharp/common.cr"

describe Analyzer::CSharp::Common do
  describe ".csharp_service_type?" do
    it "treats interface-typed parameters as DI services" do
      Analyzer::CSharp::Common.csharp_service_type?("IRepository").should be_true
      Analyzer::CSharp::Common.csharp_service_type?("IMapper").should be_true
      Analyzer::CSharp::Common.csharp_service_type?("ISender").should be_true
      Analyzer::CSharp::Common.csharp_service_type?("IAntiforgery").should be_true
      # Generic interfaces collapse to their base name first.
      Analyzer::CSharp::Common.csharp_service_type?("IRepository<CatalogItem>").should be_true
      Analyzer::CSharp::Common.csharp_service_type?("ILogger<Program>").should be_true
    end

    it "treats well-known service suffixes as DI services" do
      Analyzer::CSharp::Common.csharp_service_type?("CatalogContext").should be_true
      Analyzer::CSharp::Common.csharp_service_type?("HooksRepository").should be_true
      Analyzer::CSharp::Common.csharp_service_type?("OrderService").should be_true
      Analyzer::CSharp::Common.csharp_service_type?("AppDbContext").should be_true
    end

    it "treats known framework types as services" do
      Analyzer::CSharp::Common.csharp_service_type?("HttpContext").should be_true
      Analyzer::CSharp::Common.csharp_service_type?("CancellationToken").should be_true
    end

    it "keeps form-upload interfaces as request inputs" do
      Analyzer::CSharp::Common.csharp_service_type?("IFormFile").should be_false
      Analyzer::CSharp::Common.csharp_service_type?("IFormFileCollection").should be_false
    end

    it "does not flag request DTOs or value types" do
      Analyzer::CSharp::Common.csharp_service_type?("CreateOrderRequest").should be_false
      Analyzer::CSharp::Common.csharp_service_type?("CatalogItem").should be_false
      Analyzer::CSharp::Common.csharp_service_type?("string").should be_false
      Analyzer::CSharp::Common.csharp_service_type?("int").should be_false
      # Acronym value types (I-P-A) must not be caught by the interface rule.
      Analyzer::CSharp::Common.csharp_service_type?("IPAddress").should be_false
    end
  end
end
