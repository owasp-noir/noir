// Namespace module that re-exports endpoint structs. Instantiation sites
// reach the structs through this alias (`Endpoints.Comments`), exercising the
// namespaced-type path binding.
pub const Comments = @import("endpoints/comments.zig");
