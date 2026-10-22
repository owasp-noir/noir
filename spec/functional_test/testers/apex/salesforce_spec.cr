require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/services/apexrest/Account/*", "GET", [
    Param.new("id", "", "query"),
    Param.new("fields", "", "query"),
    Param.new("X-Trace-Id", "", "header"),
  ]),
  Endpoint.new("/services/apexrest/Account/*", "POST", [
    Param.new("name", "", "json"),
    Param.new("phone", "", "json"),
  ]),
  Endpoint.new("/services/apexrest/Account/*", "DELETE"),
  # Static @AuraEnabled methods of the top-level class only: instance
  # methods, inner-class members and @isTest classes are not actions.
  Endpoint.new("/aura#apex://CaseController/ACTION$getCases", "POST", [
    Param.new("status", "", "json"),
  ]),
  Endpoint.new("/aura#apex://CaseController/ACTION$updateCase", "POST", [
    Param.new("caseId", "", "json"),
    Param.new("fields", "", "json"),
  ]),
  Endpoint.new("/services/Soap/class/LeadService#createLead", "POST", [
    Param.new("SOAPAction", "", "header"),
    Param.new("Content-Type", "text/xml; charset=utf-8", "header"),
    Param.new("lastName", "", "json"),
    Param.new("company", "", "json"),
  ]),
]

FunctionalTester.new("fixtures/apex/salesforce/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
