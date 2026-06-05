require "../../models/tagger"
require "../../models/endpoint"

# Flags endpoints that accept personally identifiable information (PII)
# or other sensitive personal data. These endpoints are prime review
# targets for data exposure, broken object-level authorization, and
# sensitive-data logging — knowing *which* routes touch PII lets a
# reviewer (or an AI consumer) prioritize accordingly.
class PiiTagger < Tagger
  # Unambiguous, high-signal identifiers. A single one is enough to flag
  # the endpoint because these names rarely appear outside a PII context.
  STRONG_NAMES = Set{
    "ssn", "social_security", "social_security_number",
    "credit_card", "creditcard", "credit_card_number", "creditcardnumber",
    "card_number", "cardnumber", "card_no", "cardno",
    "cc_number", "ccnumber", "cvv", "cvc", "cvv2", "card_cvv",
    "card_security_code", "cardholder_name", "card_holder",
    "card_expiry", "card_expiration",
    "passport", "passport_number", "passport_no", "passportno",
    "national_id", "nationalid", "national_identity",
    "national_insurance_number", "tax_id", "taxid",
    "tax_number", "taxnumber", "aadhaar", "aadhar",
    "aadhaar_number", "aadhar_number",
    "drivers_license", "driver_license", "license_number",
    "iban", "bank_account", "bank_account_number", "routing_number",
    "sort_code",
    "date_of_birth", "dob", "birthdate", "birth_date",
  }

  # Single, unambiguous tokens. Matched anywhere in a (normalized) param
  # name so compound names like `userSsn`, `customer_cvv`, or
  # `applicantPassport` are caught without enumerating every prefix.
  STRONG_TOKENS = Set{
    "ssn", "cvv", "cvc", "cvv2", "iban", "passport", "dob",
    "aadhaar", "aadhar",
  }

  # Weaker individually (a single one shows up in countless benign
  # forms), so require at least two before tagging.
  MEDIUM_NAMES = Set{
    "email", "e_mail", "email_address", "phone", "phone_number",
    "phone_no", "mobile", "mobile_number", "mobile_phone", "cell_phone",
    "telephone",
    "first_name", "last_name", "full_name", "fullname", "given_name",
    "family_name", "middle_name", "maiden_name",
    "address", "street_address", "mailing_address", "billing_address",
    "shipping_address", "home_address",
    "postal_code", "zip", "zipcode", "zip_code",
    "gender", "nationality", "birthday", "place_of_birth",
    "marital_status",
  }

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "pii"
  end

  def perform(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      param_names = endpoint.params.map { |param| normalize_param_name(param.name) }.to_set

      has_strong = !(STRONG_NAMES & param_names).empty? ||
                   param_names.any? { |name| name.split('_').any? { |token| STRONG_TOKENS.includes?(token) } }
      medium_hits = (MEDIUM_NAMES & param_names).size

      check = has_strong || medium_hits >= 2

      if check
        tag = Tag.new(
          "pii",
          "Endpoint handles personally identifiable information (PII) or sensitive personal data; review for data exposure, broken object-level authorization, and sensitive-data logging.",
          "PII"
        )
        endpoint.add_tag(tag)
      end
    end
  end

  # Fold camelCase, separators, and casing into one snake_case form so a
  # param written as `firstName`, `First-Name`, or `first_name` all match
  # the lists, which are kept in snake_case. camelCase boundaries get an
  # underscore *before* separators are unified; digit runs are left
  # intact so `cvv2` survives.
  private def normalize_param_name(name : String) : String
    name
      .gsub(/([a-z0-9])([A-Z])/) { "#{$1}_#{$2}" }
      .gsub(/([A-Z]+)([A-Z][a-z])/) { "#{$1}_#{$2}" }
      .downcase
      .gsub(/[^a-z0-9]+/, "_")
      .strip('_')
  end
end
