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
    "credit_card", "creditcard", "card_number", "cardnumber",
    "cc_number", "ccnumber", "cvv", "cvc", "cvv2", "card_cvv",
    "card_security_code",
    "passport", "passport_number", "national_id", "nationalid",
    "national_identity", "tax_id", "taxid",
    "drivers_license", "driver_license", "license_number",
    "iban", "bank_account", "routing_number",
    "date_of_birth", "dob", "birthdate", "birth_date",
  }

  # Weaker individually (a single one shows up in countless benign
  # forms), so require at least two before tagging.
  MEDIUM_NAMES = Set{
    "email", "e_mail", "phone", "phone_number", "mobile", "telephone",
    "first_name", "last_name", "full_name", "fullname", "given_name",
    "family_name", "address", "street_address", "postal_code", "zip",
    "zipcode", "zip_code", "gender", "nationality",
  }

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "pii"
  end

  def perform(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      param_names = endpoint.params.map { |param| normalize_param_name(param.name) }.to_set

      has_strong = !(STRONG_NAMES & param_names).empty?
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

  private def normalize_param_name(name : String) : String
    name.downcase.tr("-", "_")
  end
end
