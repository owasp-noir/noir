def banner
  content = <<-CONTENT
              .__
  ____   ____ |__|______
 /    \\ /  _ \\|  \\_  __ \\
|   |  (  <♠️> )  ||  | \\/
|___|  /\\____/|__||__|
     \\/                 v#{Noir::VERSION}
CONTENT
  STDERR.puts content
  STDERR.puts ""
end
