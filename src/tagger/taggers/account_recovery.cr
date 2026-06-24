require "../../models/tagger"
require "../../models/endpoint"

# Flags credential-management and account-recovery endpoints — password
# reset/change, forgot-password, email change, MFA/2FA enrollment, OTP,
# and account verification/recovery. These are the classic account-
# takeover surface: review for reset-token leakage, host-header
# injection in reset links, account enumeration, missing rate limiting,
# and weak step-up verification.
class AccountRecoveryTagger < Tagger
  # Path segments that on their own mark a credential/recovery action.
  # `password`/`mfa`/`otp`/`forgot` are not benign as a standalone path
  # component. `recover`/`recovery` are intentionally *not* here — they
  # collide with disaster/backup/data recovery — and are matched in the
  # weak tier instead (so `/account/recovery` tags but `/disaster-recovery`
  # does not).
  STRONG_PATH_PARTS = Set{
    "password", "passwd", "forgot", "mfa", "2fa", "totp", "otp",
    # WebAuthn / FIDO2 passkey ceremonies are credential registration and
    # step-up authentication — squarely credential-management. These
    # survive the separator split as whole segments.
    "webauthn", "passkey", "passkeys",
  }

  # Spelled-out multi-factor path words. The generic separator split turns
  # `two-factor` into the harmless tokens `[two, factor]`, so the `mfa`/`2fa`
  # forms above never match these. Checked against separator-stripped slash
  # segments instead, so `two-factor`, `two_factor`, and `twofactor` (and
  # the `second-`/`multi-` spellings) all match.
  STRONG_SQUISHED_SEGMENTS = Set{"twofactor", "multifactor", "secondfactor"}

  # Parameter names that mark a credential change or a recovery/step-up
  # code regardless of the route.
  STRONG_PARAM_NAMES = Set{
    "new_password", "old_password", "current_password",
    "password_confirmation", "password_confirm", "reset_token",
    "reset_password_token", "otp", "otp_code", "mfa_code", "totp_code",
    "verification_code", "recovery_code", "confirmation_token",
  }

  # Weaker, generic action words. Tag only when two *distinct* weak
  # tokens co-occur (e.g. `/verify-email`, `/change-email`,
  # `/account/recovery`), so a bare `/reset` or `/confirm` on an
  # unrelated resource is not flagged. `change`/`update` pair with
  # `email`/`username` to catch the email-change ATO vector.
  WEAK_PATH_PARTS = Set{
    "verify", "verification", "confirm", "confirmation", "resend",
    "reset", "email", "username", "change", "update", "phone",
    "account", "recover", "recovery",
  }

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "account_recovery"
  end

  def perform(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      param_names = endpoint.params.map { |param| normalize_param_name(param.name) }.to_set
      url_segments = url_parts(endpoint.url)

      has_strong = !(STRONG_PARAM_NAMES & param_names).empty? ||
                   url_segments.any? { |part| STRONG_PATH_PARTS.includes?(part) } ||
                   mfa_squished_segment?(endpoint.url)

      weak_tokens = Set(String).new
      url_segments.each do |part|
        weak_tokens << part if WEAK_PATH_PARTS.includes?(part)
      end

      check = has_strong || weak_tokens.size >= 2

      if check
        tag = Tag.new(
          "account_recovery",
          "Credential-management or account-recovery endpoint (password reset/change, email change, MFA/OTP, verification); classic account-takeover surface — review for reset-token leakage, host-header injection in reset links, account enumeration, and missing rate limiting.",
          "AccountRecovery"
        )
        endpoint.add_tag(tag)
      end
    end
  end

  # Match `two-factor` / `second-factor` / `multi-factor` (and their `_` or
  # no-separator spellings) as whole slash segments, without the generic
  # separator split fragmenting them into benign tokens. Exact membership
  # after stripping in-segment punctuation, so `/twofactorsomething` does
  # not match.
  private def mfa_squished_segment?(url : String) : Bool
    path = url.split("?", 2)[0].split("#", 2)[0]
    path.downcase.split("/").any? do |segment|
      STRONG_SQUISHED_SEGMENTS.includes?(segment.gsub(/[^a-z0-9]/, ""))
    end
  end
end
