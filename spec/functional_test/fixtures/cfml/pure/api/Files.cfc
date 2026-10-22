component {

	// CFML has no backslash escape, so this default is the eleven-character
	// string `C:\uploads\`: the literal ends at the quote before the comma,
	// and `mask` is a second argument rather than part of the first.
	remote array function listUploads( string folder = "C:\uploads\", string mask = "*.pdf" ) {
		return directoryList( arguments.folder, false, "name", arguments.mask );
	}

	// A quote inside a CFML string is written by doubling it, and the comma
	// inside that literal is not an argument separator.
	remote string function describe( string label = "report ""Q1"", final", numeric page = 1 ) {
		return arguments.label & arguments.page;
	}

}
