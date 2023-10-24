module NoirTechs
  TECHS = {
    :crystal_kemal => {
      :language  => "Crystal",
      :framework => "Kemal",
      :similar   => ["kemal", "crystal-kemal", "crystal_kemal"],
    },
    :cs_aspnet_mvc => {
      :language  => "C#",
      :framework => "ASP.NET MVC",
      :similar   => ["asp.net mvc", "cs-aspnet-mvc", "cs_aspnet_mvc", "c# asp.net mvc", "c#-asp.net-mvc", "c#_aspnet_mvc"],
    },
    :go_echo => {
      :language  => "Go",
      :framework => "Echo",
      :similar   => ["echo", "go-echo", "go_echo"],
    },
    :go_gin => {
      :language  => "Go",
      :framework => "Gin",
      :similar   => ["gin", "go-gin", "go_gin"],
    },
    :java_jsp => {
      :language  => "Java",
      :framework => "JSP",
      :similar   => ["jsp", "java-jsp", "java_jsp"],
    },
    :java_spring => {
      :language  => "Java",
      :framework => "Spring",
      :similar   => ["spring", "java-spring", "java_spring"],
    },
    :java_armeria => {
      :language  => "Java",
      :framework => "Armeria",
      :similar   => ["armeria", "java-armeria", "java_armeria"],
    },
    :kotlin_spring => {
      :language  => "Kotlin",
      :framework => "Spring",
      :similar   => ["spring", "kotlin-spring", "kotlin_spring"],
    },
    :js_express => {
      :language  => "JavaScript",
      :framework => "Express",
      :similar   => ["express", "js-express", "js_express"],
    },
    :php_pure => {
      :language  => "PHP",
      :framework => "",
      :similar   => ["php", "php-pure", "php_pure"],
    },
    :python_django => {
      :language  => "Python",
      :framework => "Django",
      :similar   => ["django", "python-django", "python_django"],
    },
    :python_flask => {
      :language  => "Python",
      :framework => "Flask",
      :similar   => ["flask", "python-flask", "python_flask"],
    },
    :python_fastapi => {
      :language  => "Python",
      :framework => "FastAPI",
      :similar   => ["fastapi", "python-fastapi", "python_fastapi"],
    },
    :ruby_rails => {
      :language  => "Ruby",
      :framework => "Rails",
      :similar   => ["rails", "ruby-rails", "ruby_rails"],
    },
    :ruby_sinatra => {
      :language  => "Ruby",
      :framework => "Sinatra",
      :similar   => ["sinatra", "ruby-sinatra", "ruby_sinatra"],
    },
    :rust_axum => {
      :language  => "Rust",
      :framework => "Axum",
      :similar   => ["axum", "rust-axum", "rust_axum"],
    },
    :oas2 => {
      :format  => ["JSON", "YAML"],
      :similar => ["oas 2.0", "oas_2_0", "swagger 2.0", "swagger_2_0", "swagger"],
    },
    :oas3 => {
      :format  => ["JSON", "YAML"],
      :similar => ["oas 3.0", "oas_3_0"],
    },
    :raml => {
      :format  => ["YAML"],
      :similar => ["raml"],
    },
  }

  def self.get_techs
    TECHS
  end

  def self.similar_to_tech(word)
    TECHS.each do |key, value|
      if value[:similar].includes? word.downcase
        return key.to_s
      end
    end

    ""
  end
end
