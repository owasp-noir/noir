component {

	function configure() {
		var sitePrefix = "/sites/:site";
		var skipped = "new,edit";

		// Verb-agnostic: the handler's allowedMethods decides.
		route( "/", "main.index" );

		// Explicit verbs
		get( "/whoami", "auth.whoami" );
		post( "/login", "auth.login" );

		// Standard resource expansion
		resources( "photos" );

		// Named arguments, an interpolated local, and dropped actions
		resources(
			resource = "comments",
			pattern  = "#sitePrefix#/comments",
			except   = "new,edit"
		);

		// Fluent target
		route( "/render/:format" ).to( "actionRendering.index" );

		// Inline placeholder constraints must not leak into the URL
		route( "/legacy/:id-numeric{2}" ).to( "main.legacy" );

		// A group prefixes every route declared inside its closure, and
		// `withAction` names one action per verb.
		group( { pattern : "/admin" }, function( options ){
			route( "/reports" ).to( "reports.index" );
			route( "/reports/:id" ).withAction( { get : "show", delete : "remove" } );
		} );

		// A namespace is reachable only where a route mounts it; the mount
		// itself is not a route.
		route( "/v2" ).toNamespaceRouting( "v2" );
		group( { namespace : "v2" }, function( options ){
			route( "/ping" ).to( "diagnostics.ping" );
		} );

		// `except` passed by name rather than as a literal.
		resources( resource = "tags", except = skipped );
	}

}
