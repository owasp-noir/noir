/**
 * A ColdBox app's remote proxy. `access="remote"` methods stay callable
 * over HTTP whatever framework fronts the application, and the framework
 * router never mentions them — so the generic CFML analyzer still has to
 * report these even though ColdBox owns the .cfm surface.
 */
component {

	remote string function ping( string token = "" ) {
		return "pong";
	}

	private function internalOnly() {
	}

}
