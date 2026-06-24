require "../../models/tagger"
require "../../models/endpoint"

# Flags payment / financial transaction endpoints. These routes carry
# direct monetary impact, so they are prime targets for business-logic
# flaws (amount/price tampering, currency confusion, negative amounts),
# IDOR on financial records, and replay. Surfacing them helps a reviewer
# focus on the highest-stakes surface.
class PaymentTagger < Tagger
  # Path segments that strongly imply a payment/financial surface.
  # Matched as whole path segments after splitting on `/`, `-`, `_`, `.`.
  # `withdrawal(s)` (the noun) stays here; the bare verb `withdraw` is
  # ambiguous (withdraw an application/registration/bid) and lives below.
  STRONG_PATH_PARTS = Set{
    "payment", "payments", "checkout", "billing", "invoice", "invoices",
    "refund", "refunds", "payout", "payouts", "withdrawal", "withdrawals",
    "paypal", "stripe", "braintree", "pay", "purchase", "purchases",
  }

  # Path segments that often — but not always — mean money: a DB
  # "transaction", a newsletter/web-push "subscription", a battery
  # "charge", a non-financial "withdraw"/"transfer", an unpaid "order".
  # Require a corroborating money parameter before flagging.
  AMBIGUOUS_PATH_PARTS = Set{
    "charge", "charges", "transaction", "transactions",
    "subscription", "subscriptions", "withdraw", "transfer", "transfers",
    "deposit", "deposits", "wallet", "wallets", "order", "orders",
  }

  # Parameter names that strongly imply payment handling on their own
  # (card data, gateway tokens, payment-method references, bank details).
  STRONG_PARAM_NAMES = Set{
    "card_number", "cardnumber", "cc_number", "ccnumber",
    "cvv", "cvc", "cvv2", "cvn", "csc", "security_code",
    "card_security_code", "card_cvc", "card_expiry", "card_holder",
    "cardholder_name", "payment_method", "payment_method_id",
    "payment_method_nonce", "payment_intent", "setup_intent",
    "stripe_token", "paypal_token", "card_token",
    "iban", "routing_number", "sort_code",
  }

  # Generic money parameters. Weak on their own (and so never trip the
  # tagger by themselves), but enough to corroborate an ambiguous path.
  MONEY_PARAM_NAMES = Set{
    "amount", "currency", "currency_code", "price", "total",
    "subtotal", "balance", "total_amount", "amount_due", "grand_total",
  }

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "payment"
  end

  def perform(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      param_names = endpoint.params.map { |param| normalize_param_name(param.name) }.to_set

      url_segments = url_parts(endpoint.url)
      is_payment_url = url_segments.any? { |part| STRONG_PATH_PARTS.includes?(part) }
      has_strong_param = !(STRONG_PARAM_NAMES & param_names).empty?
      # `amount` and `currency` are each common in isolation, but the
      # pair almost always marks a money-moving request.
      has_amount_currency = param_names.includes?("amount") &&
                            (param_names.includes?("currency") || param_names.includes?("currency_code"))
      # An ambiguous path (e.g. `/transactions`) only counts when a money
      # parameter corroborates it.
      ambiguous_with_money = url_segments.any? { |part| AMBIGUOUS_PATH_PARTS.includes?(part) } &&
                             !(MONEY_PARAM_NAMES & param_names).empty?

      check = is_payment_url || has_strong_param || has_amount_currency || ambiguous_with_money

      if check
        tag = Tag.new(
          "payment",
          "Payment or financial transaction endpoint; review for business-logic flaws (amount/price tampering, currency confusion), IDOR on financial records, and replay.",
          "Payment"
        )
        endpoint.add_tag(tag)
      end
    end
  end
end
