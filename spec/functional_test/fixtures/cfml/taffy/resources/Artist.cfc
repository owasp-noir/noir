<cfcomponent extends="taffy.core.resource" taffy_uri="/artist/{id}">

	<cffunction name="get" access="public" output="false">
		<cfargument name="id" type="string" required="true" />
	</cffunction>

	<cffunction name="put" access="public" output="false">
		<cfargument name="id" type="string" required="true" />
		<cfargument name="email" type="string" required="false" default="" />
	</cffunction>

	<cffunction name="delete" access="public" output="false">
		<cfargument name="id" type="string" required="true" />
	</cffunction>

</cfcomponent>
