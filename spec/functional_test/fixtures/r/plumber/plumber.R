library(plumber)

#* @get /echo
#* @param msg The message to echo
function(msg = "") {
  list(msg = paste0("The message is: '", msg, "'"))
}

#* @post /submit
#* @param username The username
#* @param password The password
function(username, password) {
  # POST method means these are body parameters
}

#* @get /users/<id:int>/posts/<post_id>
#* @param limit Query limit
function(id, post_id, limit = 10) {
  # id and post_id are path parameters, limit is a query parameter (since GET)
}

#* @put /users/<id>
#* @param name The new name
function(id, name) {
  # id is path param, name is body param (since PUT)
}

# Programmatic routes
pr() %>%
  pr_get("/hello", function() {
    "Hello World"
  }) %>%
  pr_post("/save/<key>", function(key, value) {
    # key is path param
  })

r <- pr()
r$get("/direct", function() {
  "Direct GET"
})
r$handle("DELETE", "/resource/<resource_id>", function(resource_id) {
  # resource_id is path param
})

#* The shape the official plumber template ships with: `req` and `res` are
#* injected by plumber, not sent by the client, and `...` is R's variadic
#* marker rather than a parameter name. The apostrophe in "plumber's" below
#* is load-bearing: it used to open a string literal that ran to the end of
#* the file, so nothing after it was comment-stripped.
#* @param term Search term
#* @param ... plumber's passthrough arguments, not a parameter name
#* @param req The request object
#* @get /search
function(req, res, term = "", ...) {
  list(term = term)
}

# Commented-out route. Must not be reported -- it is the assertion that the
# roxygen block above did not swallow the rest of the file.
# r$get("/internal-only", function() "secret")
