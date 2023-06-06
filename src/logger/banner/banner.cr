def banner
  content = <<-CONTENT
              .__        
  ____   ____ |__|______ 
 /    \\ /  _ \\|  \\_  __ \\
|   |  (  <_> )  ||  | \\/
|___|  /\\____/|__||__|   
     \\/                 v#{Noir::VERSION}
CONTENT
  STDERR.puts content
  STDERR.puts ""
end
