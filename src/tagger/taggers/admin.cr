require "../../models/tagger"
require "../../models/endpoint"

# Flags administrative / privileged endpoints. These are high-value
# targets for broken access control, privilege escalation, and forced
# browsing — surfacing them tells a reviewer where the blast radius of a
# missing authorization check is largest.
class AdminTagger < Tagger
  # Path segments that strongly imply an administrative surface. Matched
  # as whole path segments (after splitting on `/`, `-`, `_`, `.`) so
  # `/admin/users` matches but `/badminton` does not. `/wp-admin` and
  # `/super-admin` are covered too: the split yields an `admin` token.
  # `superadmin` (no separator) is listed explicitly since the split
  # can't recover it.
  STRONG_PATH_PARTS = Set{
    "admin", "admins", "administrator", "administration", "administrative",
    "superuser", "superadmin", "sysadmin", "backoffice", "impersonate",
    "godmode",
  }

  # Parameter names that imply a privilege/role grant regardless of the
  # route or method, e.g. a generic `/users/{id}` PATCH that accepts
  # `is_admin`. These are specific enough to flag on their own. Matched
  # separator-insensitively via `normalize_param_name`, so `is_admin`,
  # `isAdmin`, and `is-admin` all collapse to the same key.
  STRONG_PRIVILEGE_PARAM_NAMES = Set{
    "is_admin", "is_superuser", "is_superadmin", "is_staff", "is_root",
    "make_admin", "grant_admin", "admin_only", "superadmin", "sudo",
    "impersonate",
  }
  STRONG_PRIVILEGE_PARAM_NAMES_NORMALIZED =
    STRONG_PRIVILEGE_PARAM_NAMES.map(&.gsub(/[-_]/, "")).to_set

  # Weaker, more generic privilege hints. These also appear as read-only
  # filters (`GET /roles?privilege=x`, `?as_user=...` view switching), so
  # only flag them on a state-changing (non-read) method.
  WEAK_PRIVILEGE_PARAM_NAMES = Set{
    "run_as", "as_user", "elevate", "privilege", "privileged",
  }
  WEAK_PRIVILEGE_PARAM_NAMES_NORMALIZED =
    WEAK_PRIVILEGE_PARAM_NAMES.map(&.gsub(/[-_]/, "")).to_set

  READ_ONLY_METHODS = Set{"GET", "HEAD", "OPTIONS"}

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "admin"
  end

  def perform(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      is_admin_url = admin_url?(endpoint.url)
      is_write = !READ_ONLY_METHODS.includes?(endpoint.method.upcase)
      has_strong_privilege_param = endpoint.params.any? do |param|
        STRONG_PRIVILEGE_PARAM_NAMES_NORMALIZED.includes?(normalize_param_name(param.name))
      end
      has_weak_privilege_param = is_write && endpoint.params.any? do |param|
        WEAK_PRIVILEGE_PARAM_NAMES_NORMALIZED.includes?(normalize_param_name(param.name))
      end

      check = is_admin_url || has_strong_privilege_param || has_weak_privilege_param

      if check
        tag = Tag.new(
          "admin",
          "Administrative or privileged endpoint; high-value target for broken access control, privilege escalation, and forced browsing.",
          "Admin"
        )
        endpoint.add_tag(tag)
      end
    end
  end

  private def admin_url?(url : String) : Bool
    parts = url.downcase.split(/[\/\-_\.]+/).reject(&.empty?)
    parts.any? { |part| STRONG_PATH_PARTS.includes?(part) }
  end

  # Strip case and separators so snake_case (`is_admin`), kebab-case
  # (`is-admin`), and camelCase (`isAdmin`) all map to a single key.
  private def normalize_param_name(name : String) : String
    name.downcase.gsub(/[-_]/, "")
  end
end
