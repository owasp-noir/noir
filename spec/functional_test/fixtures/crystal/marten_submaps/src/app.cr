require "marten"

require "./apps/auth/routes"
require "./apps/blog/routes"
require "../config/routes"

Marten.run
