// api.cfc runs the attribute through splitURIs(), so one resource may
// answer on several paths.
component extends="taffy.core.resource" taffy:uri="/alpha,/beta" {

	function get(string q = "") {
		return rep({ method: "GET" });
	}

}
