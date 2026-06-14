require "../../../spec_helper"
require "../../../../src/utils/*"
require "../../../../src/models/endpoint.cr"
require "../../../../src/models/logger.cr"
require "../../../../src/models/tagger.cr"
require "../../../../src/tagger/taggers/account_recovery.cr"
require "yaml"

def default_tagger_options
  {
    "debug"   => YAML::Any.new(false),
    "verbose" => YAML::Any.new(false),
    "color"   => YAML::Any.new(false),
    "nolog"   => YAML::Any.new(false),
  }
end

describe "AccountRecoveryTagger" do
  describe "initialization" do
    it "creates tagger with name" do
      tagger = AccountRecoveryTagger.new(default_tagger_options)
      tagger.name.should eq("account_recovery")
    end
  end

  describe "perform" do
    it "tags a forgot-password endpoint" do
      tagger = AccountRecoveryTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/auth/forgot-password", "POST")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("account_recovery")
    end

    it "tags a Devise-style /users/password endpoint" do
      tagger = AccountRecoveryTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/users/password", "PUT")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("account_recovery")
    end

    it "tags an MFA enrollment endpoint" do
      tagger = AccountRecoveryTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/account/mfa/enable", "POST")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("account_recovery")
    end

    it "tags a password change via parameters regardless of path" do
      tagger = AccountRecoveryTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/settings", "PATCH", [
        Param.new("current_password", "", "json"),
        Param.new("new_password", "", "json"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("account_recovery")
    end

    it "tags an email verification endpoint via two weak tokens" do
      tagger = AccountRecoveryTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/verify-email", "GET")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("account_recovery")
    end

    it "tags an email-change endpoint (account-takeover vector)" do
      tagger = AccountRecoveryTagger.new(default_tagger_options)

      change = Endpoint.new("/change-email", "POST")
      update = Endpoint.new("/settings/update-email", "POST")

      tagger.perform([change, update])

      change.tags.size.should eq(1)
      change.tags[0].name.should eq("account_recovery")
      update.tags.size.should eq(1)
    end

    it "tags /account/recovery via the weak pair" do
      tagger = AccountRecoveryTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/account/recovery", "POST")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("account_recovery")
    end

    it "does not tag disaster/data-recovery infrastructure endpoints" do
      tagger = AccountRecoveryTagger.new(default_tagger_options)

      disaster = Endpoint.new("/disaster-recovery", "POST")
      data = Endpoint.new("/data/recovery/jobs", "GET")

      tagger.perform([disaster, data])

      disaster.tags.size.should eq(0)
      data.tags.size.should eq(0)
    end

    it "does not tag API-credential rotation routes" do
      tagger = AccountRecoveryTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/credentials/reset", "POST")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "does not tag a bare /reset on an unrelated resource" do
      tagger = AccountRecoveryTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/dashboard/reset", "POST")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "does not tag a benign endpoint" do
      tagger = AccountRecoveryTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/products", "GET", [
        Param.new("page", "1", "query"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "tags spelled-out multi-factor paths the bare 2fa/mfa words miss" do
      ["/two-factor/authenticator", "/two_factor/yubikey",
       "/twofactor", "/u/preferences/second-factor",
       "/account/multi-factor/enroll"].each do |path|
        tagger = AccountRecoveryTagger.new(default_tagger_options)
        endpoint = Endpoint.new(path, "POST")

        tagger.perform([endpoint])

        endpoint.tags.size.should eq(1)
        endpoint.tags[0].name.should eq("account_recovery")
      end
    end

    it "tags WebAuthn / passkey credential ceremonies" do
      ["/accounts/webauthn/assertion-options", "/session/passkey/challenge",
       "/u/create_passkey", "/passkeys"].each do |path|
        tagger = AccountRecoveryTagger.new(default_tagger_options)
        endpoint = Endpoint.new(path, "POST")

        tagger.perform([endpoint])

        endpoint.tags.size.should eq(1)
        endpoint.tags[0].name.should eq("account_recovery")
      end
    end

    it "does not tag a path that merely contains the squished form as a substring" do
      tagger = AccountRecoveryTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/twofactorial/results", "GET")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end
  end
end
