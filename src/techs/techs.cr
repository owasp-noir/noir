module NoirTechs
  TECHS = {
    :crystal_kemal => {
      :language  => "Crystal",
      :framework => "Kemal",
      :similar   => ["kemal", "crystal-kemal", "crystal_kemal"],
    },
    :go_echo => {
      :language  => "Go",
      :framework => "Echo",
      :similar   => ["echo", "go-echo", "go_echo"],
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
    :swagger => {
      :format  => ["JSON", "YAML"],
      :similar => ["swagger"],
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
