// Script syntax uses a colon, and the URI carries braces that must not
// truncate the component header.
component extends="taffy.core.resource" taffy:uri="/echo/{parentId}/child/{childId}" output="false" {

	function get(required string parentId, required string childId) output="false" {
		return rep({ method: "GET" });
	}

	// Inline per-argument validators follow the default with no comma.
	function post(string name = "" taffy_minlength="1" taffy_maxlength="255", string value = "") output="false" {
		return rep({ method: "POST" }).withStatus(201);
	}

}
