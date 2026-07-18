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
