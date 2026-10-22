require "../../spec_helper"
require "../../../src/analyzer/analyzers/java/spring_data_rest.cr"

describe "Analyzer::Java::SpringDataRest.pluralize" do
  # Expected values are Evo Inflector 1.3 `English.plural`, the default
  # Spring Data REST collection path.
  {
    "order"         => "orders",
    "person"        => "persons",
    "salesPerson"   => "salesPersons",
    "category"      => "categories",
    "day"           => "days",
    "address"       => "addresses",
    "box"           => "boxes",
    "status"        => "statuses",
    "news"          => "news",
    "timeSeries"    => "timeSeries",
    "grandChild"    => "grandChildren",
    "salesman"      => "salesmen",
    "human"         => "humans",
    "analysis"      => "analyses",
    "datum"         => "data",
    "criterion"     => "criteria",
    "shelf"         => "shelves",
    "wife"          => "wives",
    "hero"          => "heroes",
    "photo"         => "photos",
    "todo"          => "todos",
    "video"         => "videos",
    "money"         => "moneys",
    "quiz"          => "quizzes",
    "bus"           => "buses",
    "auditLogEntry" => "auditLogEntries",
  }.each do |singular, plural|
    it "#{singular} -> #{plural}" do
      Analyzer::Java::SpringDataRest.pluralize(singular).should eq plural
    end
  end
end
