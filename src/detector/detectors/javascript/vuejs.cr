require "../../../models/detector"

module Detector::Javascript
  class Vuejs < Detector
    def detect(filename : String, file_contents : String) : Bool
      # Detect Vue.js framework usage
      # Check for .vue files
      return true if filename.ends_with?(".vue")
      
      # Check for Vue Router imports and usage in .js, .ts files
      if (filename.ends_with?(".js") || filename.ends_with?(".mjs") || filename.ends_with?(".ts"))
        # Vue 3 patterns
        return true if file_contents.match(/import.*from ['"]vue['"]/)
        return true if file_contents.match(/require\(['"]vue['"]\)/)
        return true if file_contents.match(/createApp\s*\(/)
        
        # Vue Router patterns (works for both Vue 2 and Vue 3)
        return true if file_contents.match(/import.*from ['"]vue-router['"]/)
        return true if file_contents.match(/require\(['"]vue-router['"]\)/)
        return true if file_contents.match(/createRouter\s*\(/)
        return true if file_contents.match(/new VueRouter\s*\(/)
        return true if file_contents.match(/Vue\.use\s*\(\s*VueRouter\s*\)/)
        
        # Check for route definitions
        return true if file_contents.match(/routes\s*:\s*\[/)
        return true if file_contents.match(/path\s*:\s*['"]\//)
      end
      
      false
    end

    def set_name
      @name = "js_vuejs"
    end
  end
end
