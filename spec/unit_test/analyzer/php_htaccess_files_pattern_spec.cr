require "../../spec_helper"
require "../../../src/analyzer/analyzers/php/php"

class PhpHtaccessPatternHarness < Analyzer::Php::Php
  def denies_php?(text : String) : Bool
    htaccess_denies_php?(text)
  end
end

private def denies_php?(text : String) : Bool
  PhpHtaccessPatternHarness.new(create_test_options).denies_php?(text)
end

private def files_block(opening : String, body : String = "Require all denied") : String
  tag = opening.starts_with?("<FilesMatch") ? "FilesMatch" : "Files"
  "#{opening}\n  #{body}\n</#{tag}>\n"
end

# A `<FilesMatch>` that merely ends in `\.php` is a hardening idiom for a
# handful of named files (`wp-config.php`, `xmlrpc.php`); the pages beside
# them are still served. Only a pattern that takes in every `.php` file turns
# the directory's PHP off.
describe "Analyzer::Php::Php .htaccess Files patterns" do
  [
    %(<FilesMatch "^(config|settings)\\.php$">),
    %(<FilesMatch "^(wp-config|config|settings)\\.php$">),
    %(<FilesMatch "^(?:config|settings)\\.php$">),
    %(<FilesMatch "^(xmlrpc|wp-login)\\.php$">),
    %(<FilesMatch "(config|settings)\\.php$">),
    %(<FilesMatch "^wp-config\\.php$">),
    %(<FilesMatch "^config\\.php$">),
    %(<FilesMatch "^(index|admin)\\.(php|phtml)$">),
    %(<Files wp-config.php>),
    %(<Files "xmlrpc.php">),
    %(<Files ~ "^(config|settings)\\.php$">),
  ].each do |opening|
    it "does not read #{opening} as every PHP file" do
      denies_php?(files_block(opening)).should be_false
      denies_php?(files_block(opening, "SetHandler !")).should be_false
    end
  end

  [
    %(<Files *.php>),
    %(<Files "*.php">),
    %(<Files ~ "\\.php$">),
    %(<FilesMatch "\\.php$">),
    %(<FilesMatch "^.*\\.php$">),
    %(<FilesMatch ".*\\.php$">),
    %(<FilesMatch ".+\\.php$">),
    %(<FilesMatch "[^/]*\\.php$">),
    %(<FilesMatch "\\.(php|phtml|php5)$">),
    %(<FilesMatch "\\.(php5|phtml|php)$">),
    %(<FilesMatch "^.+\\.(?:php|inc)$">),
    %(<FilesMatch "(?i)\\.(?:php)$">),
  ].each do |opening|
    it "reads #{opening} as every PHP file" do
      denies_php?(files_block(opening)).should be_true
      denies_php?(files_block(opening, "SetHandler !")).should be_true
    end
  end

  it "keeps the pages of a site that hardens only its config files" do
    text = <<-HTACCESS
      <FilesMatch "^(wp-config|config|settings)\\.php$">
          Require all denied
      </FilesMatch>
      <Files "xmlrpc.php">
          Order allow,deny
          Deny from all
      </Files>
      HTACCESS

    denies_php?(text).should be_false
  end
end
