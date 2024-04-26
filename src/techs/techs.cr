module NoirTechs
  TECHS = {
    :crystal_kemal => {
      :framework => "Kemal",
      :language  => "Crystal",
      :similar   => ["kemal", "crystal-kemal", "crystal_kemal"],
    },
    :crystal_lucky => {
      :framework => "Lucky",
      :language  => "Crystal",
      :similar   => ["lucky", "crystal-lucky", "crystal_lucky"],
    },
    :cs_aspnet_mvc => {
      :framework => "ASP.NET MVC",
      :language  => "C#",
      :similar   => ["asp.net mvc", "cs-aspnet-mvc", "cs_aspnet_mvc", "c# asp.net mvc", "c#-asp.net-mvc", "c#_aspnet_mvc"],
    },
    :elixir_phoenix => {
      :framework => "Phoenix",
      :language  => "Elixir",
      :similar   => ["phoenix", "elixir-phoenix", "elixir_phoenix"],
    },
    :go_beego => {
      :framework => "Beego",
      :language  => "Go",
      :similar   => ["beego", "go-beego", "go_beego"],
    },
    :go_echo => {
      :framework => "Echo",
      :language  => "Go",
      :similar   => ["echo", "go-echo", "go_echo"],
    },
    :go_fiber => {
      :framework => "Fiber",
      :language  => "Go",
      :similar   => ["fiber", "go-fiber", "go_fiber"],
    },
    :go_gin => {
      :framework => "Gin",
      :language  => "Go",
      :similar   => ["gin", "go-gin", "go_gin"],
    },
    :har => {
      :format  => ["JSON"],
      :similar => ["har"],
    },
    :java_armeria => {
      :framework => "Armeria",
      :language  => "Java",
      :similar   => ["armeria", "java-armeria", "java_armeria"],
    },
    :java_jsp => {
      :framework => "JSP",
      :language  => "Java",
      :similar   => ["jsp", "java-jsp", "java_jsp"],
    },
    :java_spring => {
      :framework => "Spring",
      :language  => "Java",
      :similar   => ["spring", "java-spring", "java_spring"],
    },
    :js_express => {
      :framework => "Express",
      :language  => "JavaScript",
      :similar   => ["express", "js-express", "js_express"],
    },
    :js_restify => {
      :framework => "Restify",
      :language  => "JavaScript",
      :similar   => ["restify", "js-restify"],
    },
    :kotlin_spring => {
      :framework => "Spring",
      :language  => "Kotlin",
      :similar   => ["spring", "kotlin-spring", "kotlin_spring"],
    },
    :oas2 => {
      :format  => ["JSON", "YAML"],
      :similar => ["oas 2.0", "oas_2_0", "swagger 2.0", "swagger_2_0", "swagger"],
    },
    :oas3 => {
      :format  => ["JSON", "YAML"],
      :similar => ["oas 3.0", "oas_3_0"],
    },
    :php_pure => {
      :framework => "",
      :language  => "PHP",
      :similar   => ["php", "php-pure", "php_pure"],
    },
    :python_django => {
      :framework => "Django",
      :language  => "Python",
      :similar   => ["django", "python-django", "python_django"],
    },
    :python_fastapi => {
      :framework => "FastAPI",
      :language  => "Python",
      :similar   => ["fastapi", "python-fastapi", "python_fastapi"],
    },
    :python_flask => {
      :framework => "Flask",
      :language  => "Python",
      :similar   => ["flask", "python-flask", "python_flask"],
    },
    :raml => {
      :format  => ["YAML"],
      :similar => ["raml"],
    },
    :ruby_hanami => {
      :framework => "Hanami",
      :language  => "Ruby",
      :similar   => ["hanami", "ruby-hanami", "ruby_hanami"],
    },
    :ruby_rails => {
      :framework => "Rails",
      :language  => "Ruby",
      :similar   => ["rails", "ruby-rails", "ruby_rails"],
    },
    :ruby_sinatra => {
      :framework => "Sinatra",
      :language  => "Ruby",
      :similar   => ["sinatra", "ruby-sinatra", "ruby_sinatra"],
    },
    :rust_axum => {
      :framework => "Axum",
      :language  => "Rust",
      :similar   => ["axum", "rust-axum", "rust_axum"],
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
