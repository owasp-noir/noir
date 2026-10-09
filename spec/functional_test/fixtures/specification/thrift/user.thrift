# User service used by the Noir functional tests.
include "shared.thrift"
include "monitor.thrift"   // resolved through an -I search path (common/)

namespace java com.ex
namespace py ex.users

typedef i64 UserId

struct User { 1: UserId id, 2: string name }

exception NotFound {
  1: string message
}

const map<string, string> DEFAULTS = {"service": "users", "rpc": "x"}

/*
 * service Legacy {
 *   void removed(1: i32 x)
 * }
 */

service UserService extends shared.SharedService {
  User getUser(1: i64 id),
  void deleteUser(1: i64 id) throws (1: NotFound nf)

  // void commentedOut(1: i32 x),
  # void hashCommented(1: i32 x),

  list<User> searchUsers(
    1: required string query,
    2: optional map<string, list<i32>> filters,
    3: i32 limit = 20 (python.default = "20")
  ) throws (1: NotFound nf);

  oneway void logEvent(1: string event; 2: i64 timestamp)
  User updateUser(1: UserId id 2: User user) (doc.note = "no separators between args")
} (svc.owner = "users")

service HealthService extends monitor.Monitor {}
