component extends="core.resource" taffy:uri="/custom" {

	function get() {
		return rep({ method: "GET" });
	}

	function updatePartial() taffy_verb="PATCH" {
		return rep({ method: "PATCH" });
	}

	function handleOptions() taffy_verb="OPTIONS" {
		return rep({ method: "OPTIONS" });
	}

	// No verb name and no taffy_verb: not a handler.
	function buildResponse(required string payload) {
		return payload;
	}

}
