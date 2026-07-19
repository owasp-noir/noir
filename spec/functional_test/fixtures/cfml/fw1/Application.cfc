component extends="framework.one" {

	this.name = "todoapp";

	variables.framework = {
		generateSES = 'true',
		routes = [
			// A verb prefix narrows the route to that method.
			{ "$GET/todo/:id"    = "/main/get/id/:id" },
			{ "$DELETE/todo/:id" = "/main/delete/id/:id" },
			{ "$POST/todo/"      = "/main/save" },

			// No `$` prefix: the route answers every method.
			{ "/legacy/ping" = "/main/ping" },

			// `hint` labels the entry; only the second key is a route.
			{ 'hint' = 'Standard Route', '$GET/old/path' = '/new/path' },
			{ 'hint' = "Standard \" Route, with comma", '$GET/escaped/comma' = '/new/path' },

			// Expands per the framework's resourceRouteTemplates.
			{ 'hint' = 'Resource Routes', '$RESOURCES' = 'dogs' }
		]
	};

	function setupApplication() {}

}
