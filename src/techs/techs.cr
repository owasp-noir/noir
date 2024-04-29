module NoirTechs
  TECHS = {
    :crystal_kemal => {
      :framework => "Kemal",
      :language  => "Crystal",
      :similar   => ["kemal", "crystal-kemal", "crystal_kemal"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => true,
        },
        :static_path => true,
        :websocket   => false,
      },
    },
    :crystal_lucky => {
      :framework => "Lucky",
      :language  => "Crystal",
      :similar   => ["lucky", "crystal-lucky", "crystal_lucky"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => true,
        },
        :static_path => true,
        :websocket   => false,
      },
    },
    :cs_aspnet_mvc => {
      :framework => "ASP.NET MVC",
      :language  => "C#",
      :similar   => ["asp.net mvc", "cs-aspnet-mvc", "cs_aspnet_mvc", "c# asp.net mvc", "c#-asp.net-mvc", "c#_aspnet_mvc"],
      :supported => {
        :endpoint => true,
        :method   => false,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => false,
          :header => false,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => false,
      },
    },
    :elixir_phoenix => {
      :framework => "Phoenix",
      :language  => "Elixir",
      :similar   => ["phoenix", "elixir-phoenix", "elixir_phoenix"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => false,
          :header => false,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => true,
      },
    },
    :go_beego => {
      :framework => "Beego",
      :language  => "Go",
      :similar   => ["beego", "go-beego", "go_beego"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => true,
        },
        :static_path => false,
        :websocket   => false,
      },
    },
    :go_echo => {
      :framework => "Echo",
      :language  => "Go",
      :similar   => ["echo", "go-echo", "go_echo"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => true,
        },
        :static_path => true,
        :websocket   => false,
      },
    },
    :go_fiber => {
      :framework => "Fiber",
      :language  => "Go",
      :similar   => ["fiber", "go-fiber", "go_fiber"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => true,
        },
        :static_path => true,
        :websocket   => false,
      },
    },
    :go_gin => {
      :framework => "Gin",
      :language  => "Go",
      :similar   => ["gin", "go-gin", "go_gin"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => true,
        },
      },
    },
    :har => {
      :format    => ["JSON"],
      :similar   => ["har"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => true,
        },
      },
    },
    :java_armeria => {
      :framework => "Armeria",
      :language  => "Java",
      :similar   => ["armeria", "java-armeria", "java_armeria"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => false,
          :header => false,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => false,
      },
    },
    :java_jsp => {
      :framework => "JSP",
      :language  => "Java",
      :similar   => ["jsp", "java-jsp", "java_jsp"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => false,
          :cookie => false,
        },
        :static_path => true,
        :websocket   => false,
      },
    },
    :java_spring => {
      :framework => "Spring",
      :language  => "Java",
      :similar   => ["spring", "java-spring", "java_spring"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => false,
      },
    },
    :js_express => {
      :framework => "Express",
      :language  => "JavaScript",
      :similar   => ["express", "js-express", "js_express"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => true,
        },
        :static_path => false,
        :websocket   => false,
      },
    },
    :js_restify => {
      :framework => "Restify",
      :language  => "JavaScript",
      :similar   => ["restify", "js-restify"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => true,
        },
        :static_path => false,
        :websocket   => false,
      },
    },
    :kotlin_spring => {
      :framework => "Spring",
      :language  => "Kotlin",
      :similar   => ["spring", "kotlin-spring", "kotlin_spring"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => false,
          :header => false,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => false,
      },
    },
    :oas2 => {
      :format    => ["JSON", "YAML"],
      :similar   => ["oas 2.0", "oas_2_0", "swagger 2.0", "swagger_2_0", "swagger"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => true,
        },
      },
    },
    :oas3 => {
      :format    => ["JSON", "YAML"],
      :similar   => ["oas 3.0", "oas_3_0"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => true,
        },
      },
    },
    :php_pure => {
      :framework => "",
      :language  => "PHP",
      :similar   => ["php", "php-pure", "php_pure"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => false,
        },
        :static_path => true,
        :websocket   => false,
      },
    },
    :python_django => {
      :framework => "Django",
      :language  => "Python",
      :similar   => ["django", "python-django", "python_django"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => true,
        },
        :static_path => true,
        :websocket   => false,
      },
    },
    :python_fastapi => {
      :framework => "FastAPI",
      :language  => "Python",
      :similar   => ["fastapi", "python-fastapi", "python_fastapi"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => true,
        },
        :static_path => false,
        :websocket   => false,
      },
    },
    :python_flask => {
      :framework => "Flask",
      :language  => "Python",
      :similar   => ["flask", "python-flask", "python_flask"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => true,
        },
        :static_path => false,
        :websocket   => false,
      },
    },
    :raml => {
      :format    => ["YAML"],
      :similar   => ["raml"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => true,
        },
      },
    },
    :ruby_hanami => {
      :framework => "Hanami",
      :language  => "Ruby",
      :similar   => ["hanami", "ruby-hanami", "ruby_hanami"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => false,
          :header => false,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => false,
      },
    },
    :ruby_rails => {
      :framework => "Rails",
      :language  => "Ruby",
      :similar   => ["rails", "ruby-rails", "ruby_rails"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => true,
        },
        :static_path => true,
        :websocket   => false,
      },
    },
    :ruby_sinatra => {
      :framework => "Sinatra",
      :language  => "Ruby",
      :similar   => ["sinatra", "ruby-sinatra", "ruby_sinatra"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => true,
        },
        :static_path => true,
        :websocket   => false,
      },
    },
    :rust_axum => {
      :framework => "Axum",
      :language  => "Rust",
      :similar   => ["axum", "rust-axum", "rust_axum"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => true,
        },
        :static_path => false,
        :websocket   => false,
      },
    },
    :rust_rocket => {
      :framework => "Rocket",
      :language  => "Rust",
      :similar   => ["rocket", "rust-rocket", "rust_rocket"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => false,
          :header => false,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => false,
      },
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
