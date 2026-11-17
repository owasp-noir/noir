require "../../spec_helper"
require "../../../src/analyzer/engines/java_engine"

private alias JavaEngine = Analyzer::Java::JavaEngine

describe "Analyzer::Java::JavaEngine.spring6_build?" do
  {
    %(<parent><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-parent</artifactId><version>3.3.0</version></parent>) => true,
    %(<parent>\n  <artifactId>spring-boot-starter-parent</artifactId>\n  <version>2.7.18</version>\n</parent>)                                 => false,
    %(<properties><spring-boot.version>3.1.2</spring-boot.version></properties>)                                                               => true,
    %(<artifactId>spring-boot-dependencies</artifactId><version>3.2.0</version><type>pom</type>)                                               => true,
    %(<spring-framework.version>6.1.4</spring-framework.version>)                                                                              => true,
    %(<artifactId>spring-webmvc</artifactId><version>5.3.30</version>)                                                                         => false,
    %(plugins { id 'org.springframework.boot' version '3.2.0' })                                                                               => true,
    %(plugins { id("org.springframework.boot") version "2.6.3" })                                                                              => false,
    %(buildscript { ext { springBootVersion = '3.0.5' } })                                                                                     => true,
    %(classpath("org.springframework.boot:spring-boot-gradle-plugin:2.5.0"))                                                                   => false,
    %(implementation "org.springframework:spring-webmvc:6.0.0")                                                                                => true,
    # Not a literal: unknown.
    %(plugins { id 'org.springframework.boot' version "${bootVersion}" })                   => nil,
    %(plugins { alias(libs.plugins.spring.boot) })                                          => nil,
    %(<!-- <artifactId>spring-boot-starter-parent</artifactId><version>3.0.0</version> -->) => nil,
    %(dependencies { implementation 'org.springframework.boot:spring-boot-starter-web' })   => nil,
  }.each do |content, expected|
    it "reads #{content.lines.first} as #{expected.inspect}" do
      JavaEngine.spring6_build?(content).should eq(expected)
    end
  end
end
