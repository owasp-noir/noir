require "../../spec_helper"
require "../../../src/passive_scan/false_positive.cr"

# A github-token-shaped rule: a `word` matcher on variable names plus a
# `regex` matcher on the value shape, joined by `or` — mirrors the
# bundled secret rules.
private def github_rule
  PassiveScan.new(YAML.parse(<<-YAML))
    id: github-token
    info:
      name: Detect GITHUB_TOKEN
      author: [test]
      severity: critical
      description: ...
      reference: []
    matchers-condition: or
    matchers:
      - type: word
        patterns: [GITHUB_TOKEN, GH_TOKEN]
        condition: or
      - type: regex
        patterns: ['ghp_[A-Za-z0-9]{36}']
        condition: or
    category: secret
    techs: ['*']
    YAML
end

# A database-connection-string-shaped rule whose word matcher fires on
# the bare variable name `DATABASE_URL`.
private def database_rule
  PassiveScan.new(YAML.parse(<<-YAML))
    id: database-connection-string
    info:
      name: Detect DATABASE_CONNECTION_STRING
      author: [test]
      severity: high
      description: ...
      reference: []
    matchers-condition: or
    matchers:
      - type: word
        patterns: [DATABASE_URL, DB_CONNECTION_STRING]
        condition: or
      - type: regex
        patterns: ['mysql://[a-z]+:[a-z]+@[a-z.]+:[0-9]+/[a-z]+']
        condition: or
    category: secret
    techs: ['*']
    YAML
end

describe NoirPassiveScan::FalsePositive do
  describe ".suppress?(rule, line)" do
    it "keeps a line whose value-shape regex matches (real literal)" do
      NoirPassiveScan::FalsePositive.suppress?(github_rule, "GITHUB_TOKEN=ghp_1234567890abcdefghijklmnopqrstuvwx").should be_false
    end

    it "suppresses a variable name mentioned in a comment" do
      NoirPassiveScan::FalsePositive.suppress?(github_rule, "# A token other than the default GITHUB_TOKEN is needed").should be_true
      NoirPassiveScan::FalsePositive.suppress?(database_rule, "    # ensure it's using the DATABASE_URL").should be_true
      NoirPassiveScan::FalsePositive.suppress?(github_rule, "#   - GITHUB_TOKEN").should be_true
    end

    it "suppresses a variable name used as a bare string literal / reference" do
      NoirPassiveScan::FalsePositive.suppress?(database_rule, %(    name: 'DATABASE_URL',)).should be_true
      NoirPassiveScan::FalsePositive.suppress?(database_rule, %(dependencies: ['DATABASE_URL'],)).should be_true
      NoirPassiveScan::FalsePositive.suppress?(database_rule, %(@previous = ENV.delete("DATABASE_URL"))).should be_true
      NoirPassiveScan::FalsePositive.suppress?(database_rule, "$ echo $DATABASE_URL").should be_true
      NoirPassiveScan::FalsePositive.suppress?(github_rule, %(github_token: Annotated[str, typer.Option(envvar="GITHUB_TOKEN")],)).should be_true
    end

    it "keeps a genuine value assignment to a variable name" do
      # A populated connection-string assignment is a real finding even
      # though the strict mysql-only regex doesn't match it.
      NoirPassiveScan::FalsePositive.suppress?(database_rule, "DATABASE_URL: postgres://user:pass@db.example.com:5432/app").should be_false
    end

    it "keeps a PEM marker (literal secret, not a variable name)" do
      pem = PassiveScan.new(YAML.parse(<<-YAML))
        id: private-key
        info: { name: Detect PRIVATE_KEY, author: [t], severity: critical, description: ., reference: [] }
        matchers-condition: or
        matchers:
          - type: word
            patterns: ['PRIVATE_KEY', '-----BEGIN PRIVATE KEY-----']
            condition: or
        category: secret
        techs: ['*']
        YAML
      NoirPassiveScan::FalsePositive.suppress?(pem, "-----BEGIN PRIVATE KEY-----").should be_false
    end

    it "never suppresses non-secret categories" do
      info_rule = PassiveScan.new(YAML.parse(<<-YAML))
        id: ci-ref
        info: { name: x, author: [t], severity: high, description: ., reference: [] }
        matchers-condition: or
        matchers:
          - type: word
            patterns: [DATABASE_URL]
            condition: or
        category: security
        techs: ['*']
        YAML
      NoirPassiveScan::FalsePositive.suppress?(info_rule, "# mentions DATABASE_URL").should be_false
    end
  end

  describe ".suppress?" do
    it "only applies to secret-category findings" do
      line = "GH_TOKEN: ${{ github.token }}"
      NoirPassiveScan::FalsePositive.suppress?("secret", line).should be_true
      # Same line under a non-secret category is never suppressed.
      NoirPassiveScan::FalsePositive.suppress?("security", line).should be_false
      NoirPassiveScan::FalsePositive.suppress?("info", line).should be_false
    end
  end

  describe ".secret_reference?" do
    it "suppresses GitHub Actions templating expressions" do
      NoirPassiveScan::FalsePositive.secret_reference?("          GH_TOKEN: ${{ github.token }}").should be_true
      NoirPassiveScan::FalsePositive.secret_reference?("  GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}").should be_true
      NoirPassiveScan::FalsePositive.secret_reference?("env: AWS_SECRET_ACCESS_KEY=${{ secrets.AWS_SECRET_ACCESS_KEY }}").should be_true
    end

    it "suppresses runtime environment-variable accessors" do
      NoirPassiveScan::FalsePositive.secret_reference?(%(api_key = os.getenv("OPENAI_API_KEY"))).should be_true
      NoirPassiveScan::FalsePositive.secret_reference?(%(const token = process.env.GITHUB_TOKEN)).should be_true
      NoirPassiveScan::FalsePositive.secret_reference?(%(key = os.environ["AWS_ACCESS_KEY_ID"])).should be_true
      NoirPassiveScan::FalsePositive.secret_reference?(%(token = ENV["GITHUB_TOKEN"])).should be_true
      NoirPassiveScan::FalsePositive.secret_reference?(%(secret := System.getenv("AWS_SECRET_ACCESS_KEY"))).should be_true
    end

    it "suppresses shell / template variable references in value position" do
      NoirPassiveScan::FalsePositive.secret_reference?("AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID").should be_true
      NoirPassiveScan::FalsePositive.secret_reference?("password: ${DB_PASSWORD}").should be_true
      NoirPassiveScan::FalsePositive.secret_reference?("OPENAI_API_KEY=%OPENAI_API_KEY%").should be_true
      NoirPassiveScan::FalsePositive.secret_reference?("token: {{ vault_github_token }}").should be_true
    end

    it "suppresses obvious angle-bracket placeholders" do
      NoirPassiveScan::FalsePositive.secret_reference?("GITHUB_TOKEN=<your-token-here>").should be_true
      NoirPassiveScan::FalsePositive.secret_reference?(%(api_key: "<INSERT_API_KEY>")).should be_true
    end

    it "keeps hard-coded literal secrets" do
      # Real-shaped values must never be suppressed.
      NoirPassiveScan::FalsePositive.secret_reference?("GITHUB_TOKEN=ghp_1234567890abcdefghijklmnopqrstuvwx").should be_false
      NoirPassiveScan::FalsePositive.secret_reference?(%(AWS_ACCESS_KEY_ID="AKIAIOSFODNN7REALKEYX")).should be_false
      NoirPassiveScan::FalsePositive.secret_reference?(%(openai_key = "sk-proj-abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJ")).should be_false
    end

    it "keeps PEM / key blocks with no assignment separator" do
      NoirPassiveScan::FalsePositive.secret_reference?("-----BEGIN RSA PRIVATE KEY-----").should be_false
      NoirPassiveScan::FalsePositive.secret_reference?("-----BEGIN PRIVATE KEY-----").should be_false
    end

    it "keeps a literal value that merely contains a dollar sign" do
      # `$` inside an otherwise-literal password must not trigger the
      # whole-value reference rule.
      NoirPassiveScan::FalsePositive.secret_reference?(%(password = "P$ssw0rd-Real-Value-123")).should be_false
    end

    it "suppresses empty assignment values (.env.example / config stubs)" do
      NoirPassiveScan::FalsePositive.secret_reference?("AWS_ACCESS_KEY_ID=").should be_true
      NoirPassiveScan::FalsePositive.secret_reference?("AWS_SECRET_ACCESS_KEY=  ").should be_true
      NoirPassiveScan::FalsePositive.secret_reference?("GITHUB_TOKEN:").should be_true
    end

    it "suppresses single-argument env() helper calls (Laravel/Symfony/Rails)" do
      NoirPassiveScan::FalsePositive.secret_reference?(%(            'key' => env('AWS_ACCESS_KEY_ID'),)).should be_true
      NoirPassiveScan::FalsePositive.secret_reference?(%(    'secret' => env("AWS_SECRET_ACCESS_KEY"),)).should be_true
    end

    it "keeps a two-argument env() call whose default could be a literal" do
      # `env('KEY', 'maybe-a-real-default')` must not be suppressed — the
      # second argument can hold a hard-coded fallback secret.
      NoirPassiveScan::FalsePositive.secret_reference?(%('key' => env('AWS_ACCESS_KEY_ID', 'AKIAREALFALLBACKKEY1'))).should be_false
    end

    it "keeps a populated value that uses the => hash-arrow separator" do
      NoirPassiveScan::FalsePositive.secret_reference?(%('key' => 'AKIAIOSFODNN7REALKEYX')).should be_false
    end

    it "suppresses documentation placeholder values" do
      NoirPassiveScan::FalsePositive.secret_reference?("AWS_ACCESS_KEY_ID=your-access-key-id").should be_true
      NoirPassiveScan::FalsePositive.secret_reference?("AWS_SECRET_ACCESS_KEY=your-secret-access-key").should be_true
      NoirPassiveScan::FalsePositive.secret_reference?("API_KEY=your_api_key").should be_true
      NoirPassiveScan::FalsePositive.secret_reference?("GITHUB_TOKEN=<token> pnpm changeset version").should be_true
      NoirPassiveScan::FalsePositive.secret_reference?("SECRET=changeme").should be_true
      NoirPassiveScan::FalsePositive.secret_reference?(%(    with_env DATABASE_URL: nil, RAILS_ENV: "development" do)).should be_true
      NoirPassiveScan::FalsePositive.secret_reference?("TOKEN=xxxxxxxx").should be_true
    end

    it "keeps real values that merely begin with similar letters" do
      # Must not over-match: a real-looking value is not a placeholder.
      NoirPassiveScan::FalsePositive.secret_reference?("DATABASE_URL=postgres://user:pass@host/db").should be_false
      NoirPassiveScan::FalsePositive.secret_reference?(%(GITHUB_TOKEN=ghp_1234567890abcdefghijklmnopqrstuvwx)).should be_false
      NoirPassiveScan::FalsePositive.secret_reference?("PROJECT=changelog-service").should be_false
    end
  end
end
