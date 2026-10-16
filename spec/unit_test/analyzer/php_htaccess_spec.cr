require "../../spec_helper"
require "../../../src/analyzer/analyzers/php/php"

class PhpHtaccessHarness < Analyzer::Php::Php
  def denies?(text : String) : Bool
    htaccess_denies_php?(text)
  end
end

private def denies?(text : String) : Bool
  PhpHtaccessHarness.new(create_test_options).denies?(text)
end

describe "Analyzer::Php::Php .htaccess" do
  # A block is a PHP-off block only when its pattern matches every plain
  # `.php` file; a pattern for some other extension must not take the
  # directory's `.php` pages away with it.
  [
    %(<Files *.php>),
    %(<Files "*.php">),
    %(<FilesMatch "\\.php$">),
    %(<FilesMatch "\\.(php|phtml)$">),
    %(<FilesMatch "\\.(php5|php)$">),
    %(<FilesMatch "(?i)\\.(?:php)$">),
  ].each do |opening|
    it "reads #{opening} as every PHP file" do
      denies?("#{opening}\n  Require all denied\n</#{opening.starts_with?("<FilesMatch") ? "FilesMatch" : "Files"}>\n").should be_true
    end
  end

  [
    %(<FilesMatch "\\.phps$">),
    %(<FilesMatch "\\.(php5|phtml)$">),
    %(<FilesMatch "\\.(phtml|php5)$">),
    %(<FilesMatch "\\.php\\.(dist|bak)$">),
    %(<FilesMatch "\\.(bak|php~)$">),
    %(<FilesMatch "\\.php[0-9]$">),
    %(<Files "*.php.bak">),
    %(<Files config.php>),
    %(<Files phpunit.xml>),
  ].each do |opening|
    it "does not read #{opening} as every PHP file" do
      denies?("#{opening}\n  Require all denied\n</#{opening.starts_with?("<FilesMatch") ? "FilesMatch" : "Files"}>\n").should be_false
    end
  end
end
