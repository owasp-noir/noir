<!--- Tag syntax: taffy_uri on the component, verb from the function name --->
<cfcomponent extends="taffy.core.resource" taffy_uri="/artists">

	<cffunction name="get" access="public" output="false">
		<cfreturn representationOf(variables.data).withStatus(200) />
	</cffunction>

	<cffunction name="post" access="public" output="false">
		<cfargument name="firstname" type="string" required="false" default="" />
		<cfargument name="lastname" type="string" required="false" default="" />
		<cfreturn representationOf(variables.data).withStatus(201) />
	</cffunction>

	<!--- Not a verb, so not a handler --->
	<cffunction name="buildRepresentation" access="private" output="false">
		<cfargument name="ignored" type="string" required="true" />
	</cffunction>

</cfcomponent>
