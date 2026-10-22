<cfscript>

	mapper()
		// `pattern` is optional and falls back to the route name.
		.get(name="login", to="sessions##new")
		.post(name="authenticate", pattern="login", to="sessions##create")

		// Bracket placeholders, not colons.
		.get(name="verify", pattern="verify/[token]", to="register##verify")

		// Full REST set.
		.resources("tweets")

		// Singular resource: no index and no key segment.
		.resource(name="account", only="show,edit,update")

		// Scoped block; every route inside is prefixed.
		.scope(path="admin", package="admin")
			.resources(name="users", nested=true)
				// Nested under the parent's key.
				.resources(name="permissions", controller="userpermissions", only="index,create")
				.member()
					.post("assume")
					.put("reset")
				.end()
			.end()
			.resources(name="roles", except="show,new,edit")
		.end()

		// Maps every controller/action pair; deliberately not expanded.
		.wildcard()

		.root(to="tweets##index", method="get")
	.end();

</cfscript>
