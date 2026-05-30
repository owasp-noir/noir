require "../../models/tagger"
require "../../models/endpoint"

# Flags administrative / privileged endpoints. These are high-value
# targets for broken access control, privilege escalation, and forced
# browsing — surfacing them tells a reviewer where the blast radius of a
# missing authorization check is largest.
class AdminTagger < Tagger
  # Path segments that strongly imply an administrative surface. Matched
  # as whole path segments (after splitting on `/`, `-`, `_`, `.`) so
  # `/admin/users` matches but `/badminton` does not. `/wp-admin` is
  # covered too: the split yields an `admin` token.
  STRONG_PATH_PARTS = Set{
    "admin", "admins", "administrator", "administration",
    "superuser", "sysadmin", "backoffice", "impersonate", "godmode",
  }

  # Parameter names that imply a privilege/role grant regardless of the
  # route or method, e.g. a generic `/users/{id}` PATCH that accepts
  # `is_admin`. These are specific enough to flag on their own.
  STRONG_PRIVILEGE_PARAM_NAMES = Set{
    "is_admin", "isadmin", "is_superuser", "is_staff", "is_root",
    "make_admin", "grant_admin", "admin_only", "sudo", "impersonate",
  }

  # Weaker, more generic privilege hints. These also appear as read-only
  # filters (`GET /roles?privilege=x`, `?as_user=...` view switching), so
  # only flag them on a state-changing (non-read) method.
  WEAK_PRIVILEGE_PARAM_NAMES = Set{
    "run_as", "as_user", "elevate", "privilege", "privileged",
  }

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
        STRONG_PRIVILEGE_PARAM_NAMES.includes?(normalize_param_name(param.name))
      end
      has_weak_privilege_param = is_write && endpoint.params.any? do |param|
        WEAK_PRIVILEGE_PARAM_NAMES.includes?(normalize_param_name(param.name))
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

  private def normalize_param_name(name : String) : String
    name.downcase.tr("-", "_")
  end
end
