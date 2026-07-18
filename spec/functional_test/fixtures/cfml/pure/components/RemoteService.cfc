<!---
	Licence header. This block mentions access="remote" on a function
	named shouldNotBeDetected() so the comment stripper is exercised.

	<cffunction name="shouldNotBeDetected" access="remote">
--->
<cfcomponent output="false">

	<cffunction name="logMessage" access="remote" returntype="boolean">
		<cfargument name="instanceName" type="string" required="true">
		<cfargument name="message" type="string" required="true">
		<cfreturn true>
	</cffunction>

	<!--- attribute order varies in the wild; `access` is not always second --->
	<cffunction name="getQueue" output="false" access="remote">
		<cfargument
			name    ="instanceName"
			type    ="string"
			required="false"
			default ="" />
		<cfreturn arrayNew(1)>
	</cffunction>

	<cffunction name="internalOnly" access="private" returntype="void">
		<cfargument name="secret" type="string" required="true">
	</cffunction>

</cfcomponent>
