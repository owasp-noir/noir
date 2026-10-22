<cfscript>
	param name="url.q" default="";

	/* legacy = form.blockComment; */
	// legacy = form.lineComment;
	category = url[ "category" ];
	writeOutput( category );
</cfscript>
