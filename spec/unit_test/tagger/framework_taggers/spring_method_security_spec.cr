require "file_utils"
require "../../../spec_helper"
require "../../../../src/analyzer/analyzers/java/spring"
require "../../../../src/analyzer/analyzers/kotlin/spring"
require "../../../../src/tagger/tagger"

private def run_method_security_analyzer(klass, files : Hash(String, String)) : Hash(String, Endpoint)
  dir = File.tempname("spring_method_security")
  locator = CodeLocator.instance
  locator.clear_all
  files.each do |name, content|
    path = File.join(dir, name)
    Dir.mkdir_p(File.dirname(path))
    File.write(path, content)
    locator.register_file(path, content)
  end
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(dir)])
  locator.scan_base_paths = [dir]
  rows = locator.with_scan_files { klass.new(options).analyze }
  SpringAuthTagger.new(options).perform(rows).to_h { |ep| {"#{ep.method.upcase} #{ep.url}", ep} }
ensure
  CodeLocator.instance.clear_all
  FileUtils.rm_rf(dir) if dir
end

private def tag_atoms(tag : Tag) : Array(Array(String))
  (tag.requires || [] of Access::Clause).map(&.any_of.map(&.to_s))
end

private def spring_auth_tags(endpoint : Endpoint) : Array(Tag)
  endpoint.tags.select(&.tagger.==("spring_auth"))
end

private def enable_config(enable_annotation : String) : String
  <<-JAVA
    package com.example;

    import org.springframework.context.annotation.Configuration;
    import org.springframework.security.config.annotation.method.configuration.*;

    @Configuration
    #{enable_annotation}
    public class MethodSecurityConfig {
    }
    JAVA
end

private def filter_chain_config(rules : String) : String
  <<-JAVA
    package com.example;

    import org.springframework.context.annotation.Bean;
    import org.springframework.context.annotation.Configuration;
    import org.springframework.security.config.annotation.web.builders.HttpSecurity;
    import org.springframework.security.web.SecurityFilterChain;

    @Configuration
    public class SecurityConfig {
        @Bean
        public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
            http.authorizeHttpRequests(auth -> auth
                #{rules}
            );
            return http.build();
        }
    }
    JAVA
end

describe "SpringAuthTagger method-security modes and order (#3814)" do
  mixed_controller = <<-JAVA
    package com.example;

    import jakarta.annotation.security.PermitAll;
    import jakarta.annotation.security.RolesAllowed;
    import org.springframework.security.access.prepost.PreAuthorize;
    import org.springframework.web.bind.annotation.GetMapping;
    import org.springframework.web.bind.annotation.RestController;

    @RestController
    @PreAuthorize("hasRole('ADMIN')")
    public class Controller {
        @PermitAll
        @GetMapping("/a")
        public String a() { return ""; }

        @RolesAllowed("USER")
        @GetMapping("/b")
        public String b() { return ""; }
    }
    JAVA

  describe "mixed annotation kinds (issue example 1)" do
    it "combines independent interceptors under @EnableMethodSecurity(jsr250Enabled = true)" do
      rows = run_method_security_analyzer(Analyzer::Java::Spring, {
        "src/main/java/com/example/MethodSecurityConfig.java" => enable_config("@EnableMethodSecurity(jsr250Enabled = true)"),
        "src/main/java/com/example/Controller.java"           => mixed_controller,
      })

      a_tags = spring_auth_tags(rows["GET /a"])
      a_tags.map(&.name).should eq(["auth"])
      a_tags[0].description.should eq("Protected by Spring @PreAuthorize on the controller class")
      tag_atoms(a_tags[0]).should eq([["role:ADMIN"]])

      b_tags = spring_auth_tags(rows["GET /b"])
      b_tags.map(&.name).should eq(["auth"])
      tag_atoms(b_tags[0]).should eq([["role:ADMIN"], ["role:USER"]])
    end

    it "lets the first metadata source decide under @EnableGlobalMethodSecurity(prePostEnabled = true, jsr250Enabled = true)" do
      rows = run_method_security_analyzer(Analyzer::Java::Spring, {
        "src/main/java/com/example/MethodSecurityConfig.java" => enable_config("@EnableGlobalMethodSecurity(prePostEnabled = true, jsr250Enabled = true)"),
        "src/main/java/com/example/Controller.java"           => mixed_controller,
      })

      a_tags = spring_auth_tags(rows["GET /a"])
      a_tags.map(&.name).should eq(["auth"])
      a_tags[0].description.should eq("Protected by Spring @PreAuthorize on the controller class")
      tag_atoms(a_tags[0]).should eq([["role:ADMIN"]])

      b_tags = spring_auth_tags(rows["GET /b"])
      b_tags.map(&.name).should eq(["auth"])
      b_tags[0].description.should eq("Protected by Spring @PreAuthorize on the controller class")
      tag_atoms(b_tags[0]).should eq([["role:ADMIN"]])
    end

    it "differs on class @RolesAllowed / @DenyAll with method @PreAuthorize(\"permitAll()\") between modes" do
      controller = <<-JAVA
        package com.example;

        import jakarta.annotation.security.DenyAll;
        import jakarta.annotation.security.RolesAllowed;
        import org.springframework.security.access.prepost.PreAuthorize;
        import org.springframework.web.bind.annotation.GetMapping;
        import org.springframework.web.bind.annotation.RestController;

        @RestController
        @RolesAllowed("ADMIN")
        public class RolesController {
            @PreAuthorize("permitAll()")
            @GetMapping("/open-pre")
            public String openPre() { return ""; }
        }

        @RestController
        @DenyAll
        public class DeniedController {
            @PreAuthorize("permitAll()")
            @GetMapping("/denied-pre")
            public String deniedPre() { return ""; }
        }
        JAVA

      ss6 = run_method_security_analyzer(Analyzer::Java::Spring, {
        "src/main/java/com/example/MethodSecurityConfig.java" => enable_config("@EnableMethodSecurity(jsr250Enabled = true)"),
        "src/main/java/com/example/Controllers.java"          => controller,
      })
      spring_auth_tags(ss6["GET /open-pre"]).map(&.name).should eq(["auth"])
      tag_atoms(spring_auth_tags(ss6["GET /open-pre"])[0]).should eq([["role:ADMIN"]])
      spring_auth_tags(ss6["GET /denied-pre"]).map(&.name).should eq(["denied"])
      tag_atoms(spring_auth_tags(ss6["GET /denied-pre"])[0]).should eq([["deny"]])

      ss5 = run_method_security_analyzer(Analyzer::Java::Spring, {
        "src/main/java/com/example/MethodSecurityConfig.java" => enable_config("@EnableGlobalMethodSecurity(prePostEnabled = true, jsr250Enabled = true)"),
        "src/main/java/com/example/Controllers.java"          => controller,
      })
      spring_auth_tags(ss5["GET /open-pre"]).map(&.name).should eq(["anonymous"])
      spring_auth_tags(ss5["GET /open-pre"])[0].requires.should be_nil
      spring_auth_tags(ss5["GET /denied-pre"]).map(&.name).should eq(["anonymous"])
      spring_auth_tags(ss5["GET /denied-pre"])[0].requires.should be_nil
    end

    it "orders @Secured ahead of JSR-250 under @EnableGlobalMethodSecurity and ANDs them under @EnableMethodSecurity" do
      controller = <<-JAVA
        package com.example;

        import jakarta.annotation.security.RolesAllowed;
        import org.springframework.security.access.annotation.Secured;
        import org.springframework.web.bind.annotation.GetMapping;
        import org.springframework.web.bind.annotation.RestController;

        @RestController
        @Secured("ROLE_ADMIN")
        public class SecuredController {
            @RolesAllowed("USER")
            @GetMapping("/mixed")
            public String mixed() { return ""; }
        }
        JAVA

      ss6 = run_method_security_analyzer(Analyzer::Java::Spring, {
        "src/main/java/com/example/MethodSecurityConfig.java" => enable_config("@EnableMethodSecurity(securedEnabled = true, jsr250Enabled = true)"),
        "src/main/java/com/example/SecuredController.java"    => controller,
      })
      tag_atoms(spring_auth_tags(ss6["GET /mixed"])[0]).should eq([["role:ADMIN"], ["role:USER"]])

      ss5 = run_method_security_analyzer(Analyzer::Java::Spring, {
        "src/main/java/com/example/MethodSecurityConfig.java" => enable_config("@EnableGlobalMethodSecurity(securedEnabled = true, jsr250Enabled = true)"),
        "src/main/java/com/example/SecuredController.java"    => controller,
      })
      tag_atoms(spring_auth_tags(ss5["GET /mixed"])[0]).should eq([["role:ADMIN"]])
    end

    it "respects which of prePostEnabled, securedEnabled and jsr250Enabled are enabled" do
      # @EnableMethodSecurity defaults: prePostEnabled = true, securedEnabled = false, jsr250Enabled = false.
      default_ss6 = run_method_security_analyzer(Analyzer::Java::Spring, {
        "src/main/java/com/example/MethodSecurityConfig.java" => enable_config("@EnableMethodSecurity"),
        "src/main/java/com/example/Controller.java"           => mixed_controller,
      })
      tag_atoms(spring_auth_tags(default_ss6["GET /a"])[0]).should eq([["role:ADMIN"]])
      tag_atoms(spring_auth_tags(default_ss6["GET /b"])[0]).should eq([["role:ADMIN"]])

      # Disabling prePostEnabled while enabling jsr250Enabled ignores @PreAuthorize.
      jsr_only = run_method_security_analyzer(Analyzer::Java::Spring, {
        "src/main/java/com/example/MethodSecurityConfig.java" => enable_config("@EnableMethodSecurity(prePostEnabled = false, jsr250Enabled = true)"),
        "src/main/java/com/example/Controller.java"           => mixed_controller,
      })
      spring_auth_tags(jsr_only["GET /a"]).map(&.name).should eq(["anonymous"])
      spring_auth_tags(jsr_only["GET /a"])[0].requires.should be_nil
      spring_auth_tags(jsr_only["GET /b"]).map(&.name).should eq(["auth"])
      tag_atoms(spring_auth_tags(jsr_only["GET /b"])[0]).should eq([["role:USER"]])

      # @EnableGlobalMethodSecurity defaults all three flags to false.
      bare_ss5 = run_method_security_analyzer(Analyzer::Java::Spring, {
        "src/main/java/com/example/MethodSecurityConfig.java" => enable_config("@EnableGlobalMethodSecurity"),
        "src/main/java/com/example/Controller.java"           => mixed_controller,
      })
      spring_auth_tags(bare_ss5["GET /a"]).should be_empty
      spring_auth_tags(bare_ss5["GET /b"]).should be_empty
    end

    it "keeps today's tag and unresolved requirement when the mode cannot be read" do
      unreadable_cases = [
        {} of String => String,
        {"src/main/java/com/example/MethodSecurityConfig.java" => enable_config("@Profile(\"prod\")\n@EnableMethodSecurity(jsr250Enabled = true)")},
        {"src/main/java/com/example/MethodSecurityConfig.java" => enable_config("@EnableMethodSecurity(jsr250Enabled = Flags.JSR250)")},
        {
          "src/main/java/com/example/ConfigA.java" => enable_config("@EnableMethodSecurity(jsr250Enabled = true)"),
          "src/main/java/com/example/ConfigB.java" => enable_config("@EnableGlobalMethodSecurity(prePostEnabled = true, jsr250Enabled = true)").sub("MethodSecurityConfig", "LegacyConfig"),
        },
        {
          "src/main/java/com/example/CustomConfig.java" => <<-JAVA,
            package com.example;
            @Configuration
            @EnableGlobalMethodSecurity(prePostEnabled = true, jsr250Enabled = true)
            public class CustomConfig extends GlobalMethodSecurityConfiguration {
                @Override
                protected MethodSecurityMetadataSource customMethodSecurityMetadataSource() {
                    return null;
                }
            }
            JAVA
        },
      ]

      unreadable_cases.each do |extra|
        rows = run_method_security_analyzer(Analyzer::Java::Spring, extra.merge({
          "src/main/java/com/example/Controller.java" => mixed_controller,
        }))

        a_tags = spring_auth_tags(rows["GET /a"])
        a_tags.map(&.name).should eq(["anonymous"])
        tag_atoms(a_tags[0]).should eq([["unresolved"]])

        b_tags = spring_auth_tags(rows["GET /b"])
        b_tags.map(&.name).should eq(["auth"])
        b_tags[0].description.should eq("Protected by Spring @RolesAllowed")
        tag_atoms(b_tags[0]).should eq([["role:USER"], ["unresolved"]])
      end
    end

    it "reads a Kotlin bodiless @EnableMethodSecurity class without bleeding a prior @Profile class" do
      config = <<-KT
        package com.example

        import org.springframework.context.annotation.Configuration
        import org.springframework.context.annotation.Profile
        import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity

        @Profile("other")
        class OtherConfig

        @Configuration
        @EnableMethodSecurity(jsr250Enabled = true)
        class MethodSecurityConfig
        KT

      controller = <<-KT
        package com.example

        import jakarta.annotation.security.PermitAll
        import jakarta.annotation.security.RolesAllowed
        import org.springframework.security.access.prepost.PreAuthorize
        import org.springframework.web.bind.annotation.GetMapping
        import org.springframework.web.bind.annotation.RestController

        @RestController
        @PreAuthorize("hasRole('ADMIN')")
        class Controller {
            @PermitAll
            @GetMapping("/a")
            fun a() = ""

            @RolesAllowed("USER")
            @GetMapping("/b")
            fun b() = ""
        }
        KT

      rows = run_method_security_analyzer(Analyzer::Kotlin::Spring, {
        "src/main/kotlin/com/example/MethodSecurityConfig.kt" => config,
        "src/main/kotlin/com/example/Controller.kt"           => controller,
      })

      spring_auth_tags(rows["GET /a"]).map(&.name).should eq(["auth"])
      tag_atoms(spring_auth_tags(rows["GET /a"])[0]).should eq([["role:ADMIN"]])
      tag_atoms(spring_auth_tags(rows["GET /b"])[0]).should eq([["role:ADMIN"], ["role:USER"]])
    end

    it "scopes method-security modes to each Maven module" do
      pom = ->(artifact : String) do
        %(<project><modelVersion>4.0.0</modelVersion><groupId>com.example</groupId><artifactId>#{artifact}</artifactId><version>1.0</version></project>)
      end
      rows = run_method_security_analyzer(Analyzer::Java::Spring, {
        "app6/pom.xml"                                             => pom.call("app6"),
        "app6/src/main/java/com/example/App6.java"                 => "@SpringBootApplication\npublic class App6 {}\n",
        "app6/src/main/java/com/example/MethodSecurityConfig.java" => enable_config("@EnableMethodSecurity(jsr250Enabled = true)"),
        "app6/src/main/java/com/example/Controller.java"           => mixed_controller.gsub("\"/b\"", "\"/ss6/b\"").gsub("\"/a\"", "\"/ss6/a\""),
        "app5/pom.xml"                                             => pom.call("app5"),
        "app5/src/main/java/com/example/App5.java"                 => "@SpringBootApplication\npublic class App5 {}\n",
        "app5/src/main/java/com/example/MethodSecurityConfig.java" => enable_config("@EnableGlobalMethodSecurity(prePostEnabled = true, jsr250Enabled = true)"),
        "app5/src/main/java/com/example/Controller.java"           => mixed_controller.gsub("\"/b\"", "\"/ss5/b\"").gsub("\"/a\"", "\"/ss5/a\""),
      })

      tag_atoms(spring_auth_tags(rows["GET /ss6/b"])[0]).should eq([["role:ADMIN"], ["role:USER"]])
      tag_atoms(spring_auth_tags(rows["GET /ss5/b"])[0]).should eq([["role:ADMIN"]])
    end
  end

  describe "inherited method annotation ahead of class annotation (issue example 2)" do
    audit_api = <<-JAVA
      package com.example;

      import org.springframework.security.access.prepost.PreAuthorize;

      public interface AuditApi {
          @PreAuthorize("hasRole('AUDITOR')")
          String report();
      }
      JAVA

    audit_controller = <<-JAVA
      package com.example;

      import org.springframework.security.access.prepost.PreAuthorize;
      import org.springframework.web.bind.annotation.GetMapping;
      import org.springframework.web.bind.annotation.RestController;

      @RestController
      @PreAuthorize("hasRole('USER')")
      public class AuditController implements AuditApi {
          @GetMapping("/report")
          @Override
          public String report() { return ""; }

          @GetMapping("/own")
          public String own() { return ""; }
      }
      JAVA

    it "picks the interface method annotation ahead of the class annotation under @EnableMethodSecurity" do
      rows = run_method_security_analyzer(Analyzer::Java::Spring, {
        "src/main/java/com/example/MethodSecurityConfig.java" => enable_config("@EnableMethodSecurity"),
        "src/main/java/com/example/AuditApi.java"             => audit_api,
        "src/main/java/com/example/AuditController.java"      => audit_controller,
      })

      report_tags = spring_auth_tags(rows["GET /report"])
      report_tags.map(&.name).should eq(["auth"])
      report_tags[0].description.should eq("Protected by Spring @PreAuthorize")
      tag_atoms(report_tags[0]).should eq([["role:AUDITOR"]])

      own_tags = spring_auth_tags(rows["GET /own"])
      own_tags[0].description.should eq("Protected by Spring @PreAuthorize on the controller class")
      tag_atoms(own_tags[0]).should eq([["role:USER"]])
    end

    it "picks the interface method annotation ahead of the class annotation under @EnableGlobalMethodSecurity" do
      rows = run_method_security_analyzer(Analyzer::Java::Spring, {
        "src/main/java/com/example/MethodSecurityConfig.java" => enable_config("@EnableGlobalMethodSecurity(prePostEnabled = true)"),
        "src/main/java/com/example/AuditApi.java"             => audit_api,
        "src/main/java/com/example/AuditController.java"      => audit_controller,
      })

      report_tags = spring_auth_tags(rows["GET /report"])
      report_tags[0].description.should eq("Protected by Spring @PreAuthorize")
      tag_atoms(report_tags[0]).should eq([["role:AUDITOR"]])
    end

    it "keeps today's class tag and leaves the inherited method annotation unresolved when mode is unknown" do
      rows = run_method_security_analyzer(Analyzer::Java::Spring, {
        "src/main/java/com/example/AuditApi.java"        => audit_api,
        "src/main/java/com/example/AuditController.java" => audit_controller,
      })

      report_tags = spring_auth_tags(rows["GET /report"])
      report_tags[0].description.should eq("Protected by Spring @PreAuthorize on the controller class")
      tag_atoms(report_tags[0]).should eq([["role:USER"], ["unresolved"]])
      report_tags[0].requires.not_nil![1].any_of[0].value.should eq("@PreAuthorize(\"hasRole('AUDITOR')\")")
    end

    it "does not let an uncertain possible override hide a farther certain annotation of the same kind" do
      base = <<-JAVA
        package com.example;

        import org.springframework.security.access.prepost.PreAuthorize;

        public class Base<T> {
            @PreAuthorize("hasRole('STAFF')")
            public String save(T item) { return ""; }

            @PreAuthorize("permitAll()")
            public String view(T item) { return ""; }
        }
        JAVA

      controller = <<-JAVA
        package com.example;

        import org.springframework.security.access.prepost.PreAuthorize;
        import org.springframework.web.bind.annotation.GetMapping;
        import org.springframework.web.bind.annotation.PostMapping;
        import org.springframework.web.bind.annotation.RestController;

        @RestController
        @PreAuthorize("hasRole('ADMIN')")
        public class ItemController extends Base<String> {
            @PostMapping("/save")
            public String save(String item) { return ""; }

            @GetMapping("/view")
            public String view(String item) { return ""; }
        }
        JAVA

      rows = run_method_security_analyzer(Analyzer::Java::Spring, {
        "src/main/java/com/example/MethodSecurityConfig.java" => enable_config("@EnableMethodSecurity"),
        "src/main/java/com/example/Base.java"                 => base,
        "src/main/java/com/example/ItemController.java"       => controller,
      })

      save_tags = spring_auth_tags(rows["POST /save"])
      save_tags.map(&.name).should eq(["auth"])
      save_tags[0].description.should eq("Protected by Spring @PreAuthorize on the controller class")
      tag_atoms(save_tags[0]).should eq([["role:ADMIN", "role:STAFF"], ["unresolved"]])
      Access.cell(Access.of(rows["POST /save"]), Access::Atom.new(:anonymous)).should be_false
      Access.cell(Access.of(rows["POST /save"]), Access::Atom.new(:role, "ADMIN")).should be_nil
      Access.cell(Access.of(rows["POST /save"]), Access::Atom.new(:role, "STAFF")).should be_nil

      view_tags = spring_auth_tags(rows["GET /view"])
      view_tags.map(&.name).should eq(["auth"])
      view_tags[0].description.should eq("Protected by Spring @PreAuthorize on the controller class")
      tag_atoms(view_tags[0]).should eq([["role:ADMIN"]])
    end

    it "does not let an uncertain earlier metadata source hide a certain later source under @EnableGlobalMethodSecurity" do
      base = <<-JAVA
        package com.example;

        import org.springframework.security.access.prepost.PreAuthorize;

        public class Base<T> {
            @PreAuthorize("hasRole('STAFF')")
            public String save(T item) { return ""; }
        }
        JAVA

      controller = <<-JAVA
        package com.example;

        import jakarta.annotation.security.RolesAllowed;
        import org.springframework.web.bind.annotation.PostMapping;
        import org.springframework.web.bind.annotation.RestController;

        @RestController
        @RolesAllowed("ADMIN")
        public class ItemController extends Base<String> {
            @PostMapping("/save")
            public String save(String item) { return ""; }
        }
        JAVA

      rows = run_method_security_analyzer(Analyzer::Java::Spring, {
        "src/main/java/com/example/MethodSecurityConfig.java" => enable_config("@EnableGlobalMethodSecurity(prePostEnabled = true, jsr250Enabled = true)"),
        "src/main/java/com/example/Base.java"                 => base,
        "src/main/java/com/example/ItemController.java"       => controller,
      })

      save_tags = spring_auth_tags(rows["POST /save"])
      save_tags.map(&.name).should eq(["auth"])
      save_tags[0].description.should eq("Protected by Spring @RolesAllowed on the controller class")
      tag_atoms(save_tags[0]).should eq([["role:ADMIN", "role:STAFF"], ["unresolved"]])
    end

    it "resolves cross-file interface inheritance in fallback mode when route_annotations are absent" do
      CodeLocator.instance.clear_all
      tmpdir = File.tempname("spring_method_fallback")
      dir = File.join(tmpdir, "src/main/java/com/example")
      Dir.mkdir_p(dir)
      {
        "MethodSecurityConfig.java" => enable_config("@EnableMethodSecurity"),
        "AuditApi.java"             => audit_api,
        "AuditController.java"      => audit_controller,
      }.each do |name, source|
        path = File.join(dir, name)
        File.write(path, source)
        CodeLocator.instance.register_path(path)
      end
      options = create_test_options
      options["base"] = YAML::Any.new(tmpdir)
      details = Details.new(PathInfo.new(File.join(dir, "AuditController.java"), 10))
      details.technology = "java_spring"
      endpoint = SpringAuthTagger.new(options).perform([Endpoint.new("/report", "GET", [] of Param, details)])[0]
      tags = spring_auth_tags(endpoint)
      tags.map(&.name).should eq(["auth"])
      tags[0].description.should eq("Protected by Spring @PreAuthorize")
      tag_atoms(tags[0]).should eq([["role:AUDITOR"]])
    ensure
      CodeLocator.instance.clear_all
      FileUtils.rm_rf(tmpdir) if tmpdir
    end

    it "handles @PostAuthorize on unsafe verbs differently between @EnableMethodSecurity and @EnableGlobalMethodSecurity" do
      controller = <<-JAVA
        package com.example;

        import org.springframework.security.access.annotation.Secured;
        import org.springframework.security.access.prepost.PostAuthorize;
        import org.springframework.web.bind.annotation.DeleteMapping;
        import org.springframework.web.bind.annotation.GetMapping;
        import org.springframework.web.bind.annotation.RestController;

        @RestController
        @Secured("ROLE_USER")
        public class DocController {
            @PostAuthorize("hasRole('AUDITOR')")
            @DeleteMapping("/docs/{id}")
            public String delete() { return ""; }

            @PostAuthorize("hasRole('AUDITOR')")
            @GetMapping("/docs/{id}")
            public String get() { return ""; }
        }
        JAVA

      ss6 = run_method_security_analyzer(Analyzer::Java::Spring, {
        "src/main/java/com/example/MethodSecurityConfig.java" => enable_config("@EnableMethodSecurity(securedEnabled = true)"),
        "src/main/java/com/example/DocController.java"        => controller,
      })
      spring_auth_tags(ss6["DELETE /docs/{id}"]).map(&.name).should eq(["auth"])
      tag_atoms(spring_auth_tags(ss6["DELETE /docs/{id}"])[0]).should eq([["role:USER"]])
      tag_atoms(spring_auth_tags(ss6["GET /docs/{id}"])[0]).should eq([["role:USER"], ["role:AUDITOR"]])

      ss5 = run_method_security_analyzer(Analyzer::Java::Spring, {
        "src/main/java/com/example/MethodSecurityConfig.java" => enable_config("@EnableGlobalMethodSecurity(prePostEnabled = true, securedEnabled = true)"),
        "src/main/java/com/example/DocController.java"        => controller,
      })
      spring_auth_tags(ss5["DELETE /docs/{id}"]).should be_empty
      tag_atoms(spring_auth_tags(ss5["GET /docs/{id}"])[0]).should eq([["role:AUDITOR"]])
    end
  end

  describe "single annotation kind preserves current tags" do
    single_kind_controller = <<-JAVA
      package com.example;

      import org.springframework.security.access.prepost.PreAuthorize;
      import org.springframework.web.bind.annotation.GetMapping;
      import org.springframework.web.bind.annotation.RestController;

      @RestController
      @PreAuthorize("hasRole('ADMIN')")
      public class SingleKindController {
          @GetMapping("/class-guard")
          public String classGuard() { return ""; }

          @PreAuthorize("hasRole('USER')")
          @GetMapping("/method-guard")
          public String methodGuard() { return ""; }

          @PreAuthorize("permitAll()")
          @GetMapping("/public")
          public String open() { return ""; }

          @PreAuthorize("denyAll()")
          @GetMapping("/denied")
          public String denied() { return ""; }
      }
      JAVA

    it "produces identical tags and requirements with or without @EnableMethodSecurity / @EnableGlobalMethodSecurity" do
      snapshot = ->(rows : Hash(String, Endpoint)) do
        rows.transform_values do |ep|
          {
            tags:       spring_auth_tags(ep).map { |t| {t.name, t.description, tag_atoms(t)} },
            resolution: ep.resolution,
          }
        end
      end

      baseline = snapshot.call(run_method_security_analyzer(Analyzer::Java::Spring, {
        "src/main/java/com/example/SingleKindController.java" => single_kind_controller,
      }))
      ss6 = snapshot.call(run_method_security_analyzer(Analyzer::Java::Spring, {
        "src/main/java/com/example/MethodSecurityConfig.java" => enable_config("@EnableMethodSecurity"),
        "src/main/java/com/example/SingleKindController.java" => single_kind_controller,
      }))
      ss5 = snapshot.call(run_method_security_analyzer(Analyzer::Java::Spring, {
        "src/main/java/com/example/MethodSecurityConfig.java" => enable_config("@EnableGlobalMethodSecurity(prePostEnabled = true)"),
        "src/main/java/com/example/SingleKindController.java" => single_kind_controller,
      }))

      ss6.should eq(baseline)
      ss5.should eq(baseline)
    end

    it "preserves current tags for a project using only JSR-250 annotations" do
      jsr_controller = <<-JAVA
        package com.example;

        import jakarta.annotation.security.DenyAll;
        import jakarta.annotation.security.PermitAll;
        import jakarta.annotation.security.RolesAllowed;
        import org.springframework.web.bind.annotation.GetMapping;
        import org.springframework.web.bind.annotation.RestController;

        @RestController
        @RolesAllowed("ADMIN")
        public class JsrController {
            @GetMapping("/class-guard")
            public String classGuard() { return ""; }

            @RolesAllowed("USER")
            @GetMapping("/method-guard")
            public String methodGuard() { return ""; }

            @PermitAll
            @GetMapping("/public")
            public String open() { return ""; }

            @DenyAll
            @GetMapping("/denied")
            public String denied() { return ""; }
        }
        JAVA

      snapshot = ->(rows : Hash(String, Endpoint)) do
        rows.transform_values do |ep|
          {
            tags:       spring_auth_tags(ep).map { |t| {t.name, t.description, tag_atoms(t)} },
            resolution: ep.resolution,
          }
        end
      end

      baseline = snapshot.call(run_method_security_analyzer(Analyzer::Java::Spring, {
        "src/main/java/com/example/JsrController.java" => jsr_controller,
      }))
      ss6 = snapshot.call(run_method_security_analyzer(Analyzer::Java::Spring, {
        "src/main/java/com/example/MethodSecurityConfig.java" => enable_config("@EnableMethodSecurity(jsr250Enabled = true)"),
        "src/main/java/com/example/JsrController.java"        => jsr_controller,
      }))
      ss5 = snapshot.call(run_method_security_analyzer(Analyzer::Java::Spring, {
        "src/main/java/com/example/MethodSecurityConfig.java" => enable_config("@EnableGlobalMethodSecurity(jsr250Enabled = true)"),
        "src/main/java/com/example/JsrController.java"        => jsr_controller,
      }))

      ss6.should eq(baseline)
      ss5.should eq(baseline)
    end
  end

  describe "missing filter-chain rules (issue example 3)" do
    controller = <<-JAVA
      package com.example;

      import org.springframework.web.bind.annotation.GetMapping;
      import org.springframework.web.bind.annotation.RestController;

      @RestController
      public class ChainController {
          @GetMapping("/legacy/x")
          public String legacy() { return ""; }

          @GetMapping("/internal/metrics")
          public String internal() { return ""; }

          @GetMapping("/remember/me")
          public String remember() { return ""; }

          @GetMapping("/other")
          public String other() { return ""; }
      }
      JAVA

    it "reads .not().hasRole(...), .hasIpAddress(...) and .rememberMe() instead of falling through to anyRequest()" do
      rules = <<-JAVA
        .requestMatchers("/legacy/**").not().hasRole("ADMIN")
        .requestMatchers("/internal/**").hasIpAddress("10.0.0.0/8")
        .requestMatchers("/remember/**").rememberMe()
        .anyRequest().hasRole("USER")
        JAVA

      rows = run_method_security_analyzer(Analyzer::Java::Spring, {
        "src/main/java/com/example/SecurityConfig.java"  => filter_chain_config(rules),
        "src/main/java/com/example/ChainController.java" => controller,
      })

      legacy_tags = spring_auth_tags(rows["GET /legacy/x"])
      legacy_tags.map(&.name).should eq(["auth"])
      legacy_tags[0].description.should eq(%(Protected by Spring Security not().hasRole via requestMatchers("/legacy/**")))
      tag_atoms(legacy_tags[0]).should eq([["unresolved"]])
      legacy_tags[0].requires.not_nil![0].any_of[0].value.should eq(%(not().hasRole("ADMIN")))

      internal_tags = spring_auth_tags(rows["GET /internal/metrics"])
      internal_tags.map(&.name).should eq(["auth"])
      internal_tags[0].description.should eq(%(Protected by Spring Security hasIpAddress via requestMatchers("/internal/**")))
      tag_atoms(internal_tags[0]).should eq([["unresolved"]])
      internal_tags[0].requires.not_nil![0].any_of[0].value.should eq(%(hasIpAddress("10.0.0.0/8")))

      remember_tags = spring_auth_tags(rows["GET /remember/me"])
      remember_tags.map(&.name).should eq(["auth"])
      remember_tags[0].description.should eq(%(Protected by Spring Security rememberMe via requestMatchers("/remember/**")))
      tag_atoms(remember_tags[0]).should eq([["unresolved"]])
      remember_tags[0].requires.not_nil![0].any_of[0].value.should eq("rememberMe()")

      other_tags = spring_auth_tags(rows["GET /other"])
      other_tags.map(&.name).should eq(["auth"])
      other_tags[0].description.should eq("Protected by Spring Security hasRole via anyRequest()")
      tag_atoms(other_tags[0]).should eq([["role:USER"]])
    end

    it "treats negated permitAll / anonymous / anyRequest rules as unreadable guards" do
      rules = <<-JAVA
        .requestMatchers("/legacy/**").not().permitAll()
        .requestMatchers("/internal/**").not().anonymous()
        .anyRequest().not().hasRole("BANNED")
        JAVA

      rows = run_method_security_analyzer(Analyzer::Java::Spring, {
        "src/main/java/com/example/SecurityConfig.java"  => filter_chain_config(rules),
        "src/main/java/com/example/ChainController.java" => controller,
      })

      legacy = spring_auth_tags(rows["GET /legacy/x"])
      legacy.map(&.name).should eq(["auth"])
      legacy[0].description.should eq(%(Protected by Spring Security not().permitAll via requestMatchers("/legacy/**")))
      tag_atoms(legacy[0]).should eq([["unresolved"]])

      internal = spring_auth_tags(rows["GET /internal/metrics"])
      internal.map(&.name).should eq(["auth"])
      internal[0].description.should eq(%(Protected by Spring Security not().anonymous via requestMatchers("/internal/**")))
      tag_atoms(internal[0]).should eq([["unresolved"]])

      other = spring_auth_tags(rows["GET /other"])
      other.map(&.name).should eq(["auth"])
      other[0].description.should eq("Protected by Spring Security not().hasRole via anyRequest()")
      tag_atoms(other[0]).should eq([["unresolved"]])
      other[0].requires.not_nil![0].any_of[0].value.should eq(%(not().hasRole("BANNED")))
    end

    it "reads hasIpAddress and rememberMe in the Kotlin DSL" do
      kotlin_config = <<-KT
        package com.example

        import org.springframework.context.annotation.Bean
        import org.springframework.context.annotation.Configuration
        import org.springframework.security.config.annotation.web.builders.HttpSecurity
        import org.springframework.security.web.SecurityFilterChain

        @Configuration
        class KotlinSecurityConfig {
            @Bean
            fun filterChain(http: HttpSecurity): SecurityFilterChain {
                http {
                    authorizeRequests {
                        authorize("/internal/**", hasIpAddress("10.0.0.0/8"))
                        authorize("/remember/**", rememberMe)
                        authorize(anyRequest, hasRole("USER"))
                    }
                }
                return http.build()
            }
        }
        KT

      kotlin_controller = <<-KT
        package com.example

        import org.springframework.web.bind.annotation.GetMapping
        import org.springframework.web.bind.annotation.RestController

        @RestController
        class ChainController {
            @GetMapping("/internal/metrics")
            fun internal() = ""

            @GetMapping("/remember/me")
            fun remember() = ""

            @GetMapping("/other")
            fun other() = ""
        }
        KT

      rows = run_method_security_analyzer(Analyzer::Kotlin::Spring, {
        "src/main/kotlin/com/example/KotlinSecurityConfig.kt" => kotlin_config,
        "src/main/kotlin/com/example/ChainController.kt"      => kotlin_controller,
      })

      internal = spring_auth_tags(rows["GET /internal/metrics"])
      internal.map(&.name).should eq(["auth"])
      internal[0].description.should eq(%(Protected by Spring Security hasIpAddress via authorize("/internal/**")))
      tag_atoms(internal[0]).should eq([["unresolved"]])

      remember = spring_auth_tags(rows["GET /remember/me"])
      remember.map(&.name).should eq(["auth"])
      remember[0].description.should eq(%(Protected by Spring Security rememberMe via authorize("/remember/**")))
      tag_atoms(remember[0]).should eq([["unresolved"]])

      other = spring_auth_tags(rows["GET /other"])
      tag_atoms(other[0]).should eq([["role:USER"]])
    end
  end
end
