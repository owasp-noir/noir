require "../../spec_helper"
require "../../../src/passive_scan/false_positive.cr"

describe NoirPassiveScan::FalsePositive do
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
  end
end
