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

  # An unclosed opening tag makes the block regexes scan to EOF, once per tag,
  # so the cost is quadratic in the file size. Past the size cap the file is
  # not read at all.
  it "does not read an oversized .htaccess" do
    cap = Analyzer::Php::Php::HTACCESS_MAX_BYTES
    padding = "#" * (cap - 20) + "\n"

    denies?("Deny from all\n" + padding).should be_true
    denies?("Deny from all\n" + padding + padding).should be_false
  end

  # The cap is what bounds that quadratic cost, so the hostile file has to sit
  # just *under* it: anything bigger is skipped unread and proves nothing. The
  # file is the worst shape measured (a bare `<Files>` per line: 25ms at 16KB,
  # 0.35s at 64KB). The cap is pinned outright, and the timing is the best of
  # three runs against a ceiling 40x above the measurement, so a loaded CI
  # machine does not fail it but a regex that went worse than quadratic would.
  it "stays fast on a file of unclosed blocks just under the cap" do
    cap = Analyzer::Php::Php::HTACCESS_MAX_BYTES
    unit = "<Files>\n"
    hostile = unit * ((cap - 1) // unit.bytesize)
    hostile.bytesize.should be < cap
    cap.should be <= 16_384

    denies?(hostile).should be_false
    best = 3.times.min_of do
      started = Time.instant
      denies?(hostile)
      Time.instant - started
    end

    best.should be < 1.second
  end
end
