component {

	function configure(){
		// Mounted under the module entry point.
		get( "/status", "status.index" );
	}

}
