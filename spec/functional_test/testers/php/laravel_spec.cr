require "../../func_spec.cr"

# Expected endpoints for spec/functional_test/fixtures/php/laravel_sample/
expected_laravel_endpoints = [
  # --- web.php ---
  # Route::get('/', [PageController::class, 'home']);
  Endpoint.new("/", "GET"),
  # Route::get('/about', [PageController::class, 'about']);
  Endpoint.new("/about", "GET"),
  # Route::get('/users/{userId}', [ProfileController::class, 'show']);
  # - public function show(string $userId)
  Endpoint.new("/users/{userId}", "GET", query_params: [Param.new("userId", "", "path")]),
  # Route::post('/users/{userId}/contact', [ProfileController::class, 'contact']);
  # - public function contact(Request $request, string $userId)
  # - $message = $request->input('message');
  # - $subject = $request->input('subject', 'Default Subject');
  Endpoint.new("/users/{userId}/contact", "POST", query_params: [Param.new("userId", "", "path")], body_params: [Param.new("message", "", "form"), Param.new("subject", "", "form")]),

  # Route::resource('photos', PhotoController::class);
  # Controller methods: index, create, store, show, edit, update, destroy
  # StorePhotoRequest: 'title', 'image_file'
  # PhotoController::store: $request->input('caption')
  # PhotoController::update: $request->input('description')

  # GET /photos (index)
  Endpoint.new("/photos", "GET"),
  # GET /photos/create (create)
  Endpoint.new("/photos/create", "GET"),
  # POST /photos (store) - Params: title, image_file (from FormRequest), caption (from input)
  Endpoint.new("/photos", "POST", body_params: [Param.new("title", "", "form"), Param.new("image_file", "", "form"), Param.new("caption", "", "form")]),
  # GET /photos/{photo} (show)
  Endpoint.new("/photos/{photo}", "GET", query_params: [Param.new("photo", "", "path")]),
  # GET /photos/{photo}/edit (edit)
  Endpoint.new("/photos/{photo}/edit", "GET", query_params: [Param.new("photo", "", "path")]),
  # PUT /photos/{photo} (update) - Param: description
  Endpoint.new("/photos/{photo}", "PUT", query_params: [Param.new("photo", "", "path")], body_params: [Param.new("description", "", "form")]),
  # PATCH /photos/{photo} (update) - Param: description
  Endpoint.new("/photos/{photo}", "PATCH", query_params: [Param.new("photo", "", "path")], body_params: [Param.new("description", "", "form")]),
  # DELETE /photos/{photo} (destroy)
  Endpoint.new("/photos/{photo}", "DELETE", query_params: [Param.new("photo", "", "path")]),

  # --- api.php ---
  # Route::get('/status', function () { ... });
  Endpoint.new("/status", "GET"),
  # Route::post('/echo', function (Request $request) { return response()->json($request->all()); });
  # Assuming $request->all() implies generic body params. The analyzer might create a generic param or none if it can't determine specifics.
  # For now, let's expect no specific named params from $request->all() unless analyzer is enhanced for it.
  Endpoint.new("/echo", "POST"),

  # Route::apiResource('tasks', TaskController::class);
  # Controller methods: index, store, show, update, destroy
  # TaskController::index: $request->query('status')
  # TaskController::store: $request->input('name'), $request->input('priority')
  # TaskController::update: $request->input('completed')

  # GET /tasks (index) - Param: status (query)
  Endpoint.new("/tasks", "GET", query_params: [Param.new("status", "", "query")]),
  # POST /tasks (store) - Params: name, priority (body)
  Endpoint.new("/tasks", "POST", body_params: [Param.new("name", "", "form"), Param.new("priority", "", "form")]),
  # GET /tasks/{task} (show)
  Endpoint.new("/tasks/{task}", "GET", query_params: [Param.new("task", "", "path")]),
  # PUT /tasks/{task} (update) - Param: completed (body)
  Endpoint.new("/tasks/{task}", "PUT", query_params: [Param.new("task", "", "path")], body_params: [Param.new("completed", "", "form")]),
  # PATCH /tasks/{task} (update) - Param: completed (body)
  Endpoint.new("/tasks/{task}", "PATCH", query_params: [Param.new("task", "", "path")], body_params: [Param.new("completed", "", "form")]),
  # DELETE /tasks/{task} (destroy)
  Endpoint.new("/tasks/{task}", "DELETE", query_params: [Param.new("task", "", "path")]),

  # Route::get('items/{itemId}/details', [ItemController::class, 'getDetails']);
  # - public function getDetails(Request $request, string $itemId)
  # - $verbose = $request->query('verbose', 'false');
  Endpoint.new("/items/{itemId}/details", "GET", query_params: [Param.new("itemId", "", "path"), Param.new("verbose", "", "query")]),
  # Route::post('items', [ItemController::class, 'createItem']);
  # - public function createItem(Request $request)
  # - $itemName = $request->input('itemName');
  # - $itemValue = $request->input('itemValue');
  Endpoint.new("/items", "POST", body_params: [Param.new("itemName", "", "form"), Param.new("itemValue", "", "form")])
]

FunctionalTester.new("fixtures/php/laravel_sample/", {
  :techs     => 1, # Expecting 'php_laravel'
  :endpoints => expected_laravel_endpoints.size,
  :tech_names => ["php_laravel"] # Explicitly check for this tech name
}, expected_laravel_endpoints).perform_tests
