component {

	function configure() {
		var sitePrefix = "/sites/:site";

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
	}

}
