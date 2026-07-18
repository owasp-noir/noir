require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect Hasura metadata" do
  options = create_test_options
  instance = Detector::Specification::Hasura.new options

  per_table = <<-YAML
    table:
      name: movies
      schema: public
    select_permissions:
      - role: public
        permission:
          columns:
            - id
            - title
          filter: {}
    YAML

  it "detects the CLI v3 per-table form" do
    instance.detect("metadata/databases/default/tables/public_movies.yaml", per_table).should be_true
  end

  it "detects a metadata directory at any depth" do
    instance.detect("backend/hasura/metadata/databases/default/tables/public_movies.yaml", per_table).should be_true
  end

  it "detects the legacy flat array form" do
    content = <<-YAML
      - table:
          name: movies
          schema: public
        select_permissions:
          - role: public
            permission:
              columns:
                - id
              filter: {}
      YAML

    instance.detect("metadata/tables.yaml", content).should be_true
  end

  it "detects rest_endpoints.yaml" do
    content = <<-YAML
      - name: getMovie
        url: movie/:id
        methods:
          - GET
        definition:
          query:
            collection_name: allowed-queries
            query_name: getMovie
      YAML

    instance.detect("metadata/rest_endpoints.yaml", content).should be_true
  end

  # `- table:` is a plausible shape in dbt, Airflow and Metabase configs.
  # The /metadata/ path segment is what rules them out.
  it "ignores a table-shaped YAML outside a metadata directory" do
    instance.detect("models/schema.yml", per_table).should be_false
    instance.detect("config/tables.yml", per_table).should be_false
  end

  it "ignores a metadata YAML with no Hasura vocabulary" do
    content = <<-YAML
      table:
        name: movies
        schema: public
      description: just a description
      YAML

    instance.detect("metadata/databases/default/tables/public_movies.yaml", content).should be_false
  end

  # The CLI v3 tables.yaml is only an index of include strings; it holds
  # no table of its own and must not be claimed.
  it "ignores an include-only tables.yaml without crashing" do
    content = <<-YAML
      - "!include public_movies.yaml"
      - "!include public_directors.yaml"
      YAML

    instance.detect("metadata/databases/default/tables/tables.yaml", content).should be_false
  end

  it "ignores metadata files that declare no table" do
    content = <<-YAML
      - name: sendEmail
        definition:
          kind: synchronous
          handler: http://localhost:3000/send
      YAML

    instance.detect("metadata/actions.yaml", content).should be_false
  end

  it "ignores malformed YAML" do
    instance.detect("metadata/tables.yaml", "table:\n  - : :\n\tbad indent").should be_false
  end

  it "ignores non-YAML extensions" do
    instance.detect("metadata/tables.json", per_table).should be_false
  end

  it "registers table and REST paths under separate locator keys" do
    locator = CodeLocator.instance
    locator.clear "hasura-tables"
    locator.clear "hasura-rest-endpoints"

    instance.detect("metadata/databases/default/tables/public_movies.yaml", per_table)
    instance.detect("metadata/rest_endpoints.yaml", <<-YAML)
      - name: getMovie
        url: movie/:id
        methods:
          - GET
      YAML

    locator.all("hasura-tables").should eq(["metadata/databases/default/tables/public_movies.yaml"])
    locator.all("hasura-rest-endpoints").should eq(["metadata/rest_endpoints.yaml"])
  end
end
