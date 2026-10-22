<cfif structKeyExists(form, "username")>
	<cfset stored = form.password>
</cfif>

<cfif isDefined("cookie.session_id")>
	<cfset sid = cookie.session_id>
</cfif>

<cfset agent = cgi.http_user_agent>
