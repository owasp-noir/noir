require "../../spec_helper"
require "../../../src/analyzer/analyzers/php/php"

class PhpHtaccessIfCrlfHarness < Analyzer::Php::Php
  def denies_dir?(text : String) : Bool
    htaccess_denies_php?(text)
  end
end

private def denies_dir?(text : String) : Bool
  PhpHtaccessIfCrlfHarness.new(create_test_options).denies_dir?(text)
end

describe "Analyzer::Php::Php .htaccess conditions and line endings" do
  # A deny inside an expression block applies to the requests the expression
  # picks out, not to the directory.
  it "does not read a deny inside <If>, <ElseIf> or <Else> as a directory deny" do
    denies_dir?(%(<If "%{HTTP_USER_AGENT} =~ /badbot/">\n  Require all denied\n</If>\n)).should be_false
    denies_dir?(%(<ElseIf "%{REQUEST_URI} =~ m#^/private#">\n  Require all denied\n</ElseIf>\n)).should be_false
    denies_dir?(%(<If "-n %{HTTP_REFERER}">\n  Require all granted\n</If>\n<Else>\n  Require all denied\n</Else>\n)).should be_false
  end

  it "still reads a deny beside an <If> block as a directory deny" do
    denies_dir?(%(<If "%{HTTP_USER_AGENT} =~ /badbot/">\n  ErrorDocument 403 /nope\n</If>\nRequire all denied\n)).should be_true
  end

  # <IfModule> / <IfDefine> are not request conditions: a deny in one is the
  # directory's deny.
  it "does not mistake <IfModule> for an expression block" do
    denies_dir?(%(<IfModule mod_authz_core.c>\n  Require all denied\n</IfModule>\n)).should be_true
  end

  it "reads a CRLF deny" do
    denies_dir?("Deny from all\r\n").should be_true
    denies_dir?("Require all denied\r\n").should be_true
    denies_dir?("Options -Indexes\r\nDeny from all  \r\nErrorDocument 403 /nope\r\n").should be_true
    denies_dir?("Require all denied\r").should be_true
  end

  it "keeps reading a CRLF file the same as an LF one" do
    denies_dir?("<Files *.php>\r\n  SetHandler !\r\n</Files>\r\n").should be_true
    denies_dir?("<Files config.php>\r\n  Require all denied\r\n</Files>\r\n").should be_false
    denies_dir?("Deny from all\r\nAllow from 127.0.0.1\r\n").should be_false
    denies_dir?("Options -Indexes\r\n").should be_false
  end
end
