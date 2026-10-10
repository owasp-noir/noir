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

# Word-only secret rule over the env names the real-world false positives
# were reported against.
private def env_names_rule
  PassiveScan.new(YAML.parse(<<-YAML))
    id: env-names
    info: {name: env names, author: [test], severity: high, description: ., reference: []}
    matchers-condition: or
    matchers:
      - type: word
        patterns: [OPENAI_API_KEY, AWS_ACCESS_KEY_ID, GH_TOKEN, GEMINI_API_KEY, ANTHROPIC_API_KEY, GITHUB_TOKEN, STRIPE_API_KEY, MONGO_URL]
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

    it "keeps a commented-out credentialed URL" do
      NoirPassiveScan::FalsePositive.suppress?(database_rule, "# DATABASE_URL=postgres://admin:S3cretPassw0rd@prod-db:5432/app").should be_false
      NoirPassiveScan::FalsePositive.suppress?(database_rule, %(// "DATABASE_URL": "redis://:Sup3rS3cret@cache:6379")).should be_false
      NoirPassiveScan::FalsePositive.suppress?(database_rule, "# DATABASE_URL=postgres://user:${DB_PASSWORD}@db/app").should be_true
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

    it "keeps a credentialed URL written to, or defaulted through, an env accessor" do
      url = "postgres://admin:S3cretPassw0rd@prod-db.internal:5432/app"
      [
        %(os.environ["DATABASE_URL"] = "#{url}"),
        %(os.environ.setdefault("DATABASE_URL", "#{url}")),
        %(ENV["DATABASE_URL"] ||= "#{url}"),
        %(process.env.DATABASE_URL = "#{url}";),
        %(DB = os.getenv("DATABASE_URL", "#{url}")),
        %('url' => env('DATABASE_URL', '#{url}'),),
        %(const db = process.env.DATABASE_URL || "#{url}";),
        %(ENV["DATABASE_URL"] = "redis://:Sup3rS3cret@cache.internal:6379/0"),
        # Control: the plain assignment was always reported.
        %(DATABASE_URL = "#{url}"),
      ].each do |line|
        NoirPassiveScan::FalsePositive.suppress?(database_rule, line).should be_false, "expected kept: #{line}"
      end
    end

    it "still suppresses env reads and test/dev values handed through env names" do
      [
        # Plain reads.
        %(url = os.environ["DATABASE_URL"]),
        %(url = os.environ.get("DATABASE_URL")),
        %(url = ENV.fetch("DATABASE_URL")),
        %(const url = process.env.DATABASE_URL;),
        %(if (process.env.DATABASE_URL === "") {),
        %(url = os.getenv("DATABASE_URL", "")),
        %(url = os.getenv("DATABASE_URL", default_url)),
        %(os.environ["DATABASE_URL"] = os.environ["TEST_DATABASE_URL"]),
        # Test/dev values written through an accessor.
        %(ENV["DATABASE_URL"] = "db.sqlite"),
        %(ENV["DATABASE_URL"] = "postgres://postgres@localhost/my_database"),
        %(ENV["DATABASE_URL"] = "postgres://user:${DB_PASSWORD}@db/app"),
        # Non-secret defaults and fallbacks.
        %(url = os.getenv("DATABASE_URL", "sqlite:///db.sqlite3")),
        %(url = os.getenv("DATABASE_URL", "<your-database-url>")),
        %(const url = process.env.DATABASE_URL ?? "localhost";),
        %(const url = process.env.DATABASE_URL || 'dev';),
        %(url = os.environ.get("DATABASE_URL") or "anonymous"),
        %(url = ENV.fetch("DATABASE_URL", "dev")),
        %(require_env("DATABASE_URL", "REDIS_URL")),
        # Format-string slots stand in for the password.
        %(url = os.getenv("DATABASE_URL", "postgresql://{}:{}@{}/{}".format(u, p, h, d))),
        %(url = os.getenv("DATABASE_URL", "postgresql://app:%s@db/app" % pw)),
        %(url = os.getenv("DATABASE_URL", "postgresql://app:%(pw)s@db/app" % cfg)),
        # Comment-line suppression is unchanged.
        %(# os.environ["DATABASE_URL"] = "postgres://admin:pw@db:5432/app"),
      ].each do |line|
        NoirPassiveScan::FalsePositive.suppress?(database_rule, line).should be_true, "expected suppressed: #{line}"
      end

      [
        %(ENV["OPENAI_API_KEY"] = "test"),
        %(ENV["OPENAI_API_KEY"] = "x"),
        %(ENV["OPENAI_API_KEY"] = "brew"),
        %(ENV["OPENAI_API_KEY"] = "sk-XXXXXXXX"),
        %(ENV["AWS_ACCESS_KEY_ID"] = "eu-west-1"),
        %(t.Setenv("GH_TOKEN", "test-token")),
        %(monkeypatch.setenv("GEMINI_API_KEY", "gemini_env_api_key")),
        %(process.env["ANTHROPIC_API_KEY"] = "pre-existing-key";),
        %(logger.warning("GITHUB_TOKEN", "is not set")),
        %(check_env("STRIPE_API_KEY", "Stripe key required")),
        %(env('GITHUB_TOKEN','forge')),
        %(mongo = os.environ.get("MONGO_URL", "mongodb://localhost:27017")),
      ].each do |line|
        NoirPassiveScan::FalsePositive.suppress?(env_names_rule, line).should be_true, "expected suppressed: #{line}"
      end
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

    # A long word run after an env accessor used to backtrack exponentially
    # against the optional bare key, hit PCRE2's match limit inside the
    # filter, and drop the whole rule for the file.
    it "does not raise on a long word run after an env accessor" do
      line = "const t = process.env.GITHUB_TOKEN#{"A" * 6000}"
      NoirPassiveScan::FalsePositive.secret_reference?(line).should be_true
    end

    it "does not treat an accessor that hands over a credentialed URL as a pure read" do
      NoirPassiveScan::FalsePositive.secret_reference?(%(url = os.getenv("DATABASE_URL", "postgres://app:S3cret@db/app"))).should be_false
      NoirPassiveScan::FalsePositive.secret_reference?(%(ENV["DATABASE_URL"] ||= "mysql://root:hunter22@db/app")).should be_false
      NoirPassiveScan::FalsePositive.secret_reference?(%(token = ENV["GITHUB_TOKEN"] || "ghp_fallback")).should be_true
      NoirPassiveScan::FalsePositive.secret_reference?(%(token = ENV["GITHUB_TOKEN"] == "x")).should be_true
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
      NoirPassiveScan::FalsePositive.secret_reference?("SHOPIFY_API_SECRET =>").should be_true
    end

    it "keeps a base64 value whose padding ends the line" do
      # The empty-assignment check used to be unanchored, so it matched any
      # line merely *ending* in `=` — which is what every padded base64
      # value does. Real secrets were dropped for having padding.
      NoirPassiveScan::FalsePositive.secret_reference?("AZURE_STORAGE_KEY=Zm9vYmFyYmF6cXV4MTIzNDU2Nzg5MA==").should be_false
      NoirPassiveScan::FalsePositive.secret_reference?("NPM_TOKEN: bnBtX3Rva2VuXzEyMzQ1Ng==").should be_false
      NoirPassiveScan::FalsePositive.secret_reference?("export VAULT_TOKEN=cy5hYmNkZWZnaGlqa2xtbm9w=").should be_false
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
