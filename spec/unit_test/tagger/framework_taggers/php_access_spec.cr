require "../../../spec_helper"
require "../../../../src/tagger/framework_taggers/php/php_access"

# As a clause stores it: atoms deduplicated and sorted, an unresolved atom
# with its fragment.
private def read(cnf : Access::CNF) : Array(Array(String))
  cnf.map(&.uniq.sort!.map { |atom| atom.kind.unresolved? ? "unresolved:#{atom.value}" : atom.to_s })
end

private def read(clauses : Array(Access::Clause)) : Array(Array(String))
  read(clauses.map(&.any_of))
end

describe PhpAccess do
  describe ".symfony_attribute" do
    {
      "ROLE_ADMIN"                   => [["role:ROLE_ADMIN"]],
      "ROLE_app.editor"              => [["role:ROLE_app.editor"]],
      "IS_AUTHENTICATED"             => [["authenticated"]],
      "IS_AUTHENTICATED_FULLY"       => [["authenticated"]],
      "IS_AUTHENTICATED_REMEMBERED"  => [["authenticated"]],
      "IS_IMPERSONATOR"              => [["authenticated"], ["unresolved:IS_IMPERSONATOR"]],
      "PUBLIC_ACCESS"                => [] of Array(String),
      "IS_AUTHENTICATED_ANONYMOUSLY" => [] of Array(String),
      "POST_EDIT"                    => [["unresolved:POST_EDIT"]],
      "@parts.read"                  => [["unresolved:@parts.read"]],
    }.each do |attribute, expected|
      it "reads #{attribute}" do
        read(PhpAccess.symfony_attribute(attribute)).should eq(expected)
      end
    end
  end

  describe ".symfony_attributes" do
    {
      "#[IsGranted('ROLE_ADMIN')]"                                       => [["role:ROLE_ADMIN"]],
      "#[IsGranted(attribute: 'ROLE_ADMIN', statusCode: 404)]"           => [["role:ROLE_ADMIN"]],
      "#[IsGranted('ROLE_ADMIN', 'post')]"                               => [["role:ROLE_ADMIN"]],
      "#[IsGranted(subject: 'post', attribute: 'POST_EDIT')]"            => [["unresolved:POST_EDIT"]],
      "#[IsGranted('ROLE_USER')]\n#[IsGranted('ROLE_ADMIN')]"            => [["role:ROLE_USER"], ["role:ROLE_ADMIN"]],
      "#[Route('/a'), IsGranted('ROLE_USER')]"                           => [["role:ROLE_USER"]],
      "#[IsGranted(AuthenticatedVoter::IS_AUTHENTICATED_FULLY)]"         => [["authenticated"]],
      "#[IsGranted(User::ROLE_ADMIN)]"                                   => [["authenticated"], ["unresolved:User::ROLE_ADMIN"]],
      "#[IsGranted(PostVoter::EDIT, 'post')]"                            => [["unresolved:PostVoter::EDIT"]],
      "#[IsGranted(new Expression('is_granted(\"ROLE_A\") or x'))]"      => [["authenticated"], ["unresolved:new Expression('is_granted(\"ROLE_A\") or x')"]],
      "#[IsGranted('PUBLIC_ACCESS')]"                                    => [] of Array(String),
      "/**\n * @IsGranted(\"ROLE_ADMIN\")\n */"                          => [["role:ROLE_ADMIN"]],
      "#[Security(\"is_granted('ROLE_ADMIN')\")]"                        => [["authenticated"], ["unresolved:Security(\"is_granted('ROLE_ADMIN')\")"]],
      "#[Security(name: 'Bearer')]"                                      => [] of Array(String),
      "#[IsGranted(\n  'ROLE_ADMIN'"                                     => [["authenticated"], ["unresolved:IsGranted"]],
      "#[IsGranted(\"ROLE_{$x}\")]"                                      => [["authenticated"], ["unresolved:\"ROLE_{$x}\""]],
      "#[IsGranted(attribute: 'ROLE_A'), IsGranted('IS_AUTHENTICATED')]" => [["role:ROLE_A"], ["authenticated"]],
    }.each do |text, expected|
      it "reads #{text.inspect}" do
        read(PhpAccess.symfony_attributes(text)).should eq(expected)
      end
    end
  end

  describe ".symfony_refusals" do
    deny = "$this->denyAccessUnlessGranted('ROLE_ADMIN')"
    {
      {"\n  #{deny};\n  return 1;\n", true}                                                                     => [["role:ROLE_ADMIN"]],
      {"\n  $post = $repo->find($id);\n  #{deny};\n", true}                                                     => [["role:ROLE_ADMIN"]],
      {"\n  if ($x) {\n    #{deny};\n  }\n", true}                                                              => [["authenticated"], ["unresolved:#{deny}"]],
      {"\n  if ($x) #{deny};\n", true}                                                                          => [["authenticated"], ["unresolved:#{deny}"]],
      {"\n  if ($x) { return 1; }\n  #{deny};\n", true}                                                         => [["authenticated"], ["unresolved:#{deny}"]],
      {"\n  #{deny};\n", false}                                                                                 => [["authenticated"], ["unresolved:#{deny}"]],
      {"\n  try {\n    #{deny};\n  } catch (AccessDeniedException $e) {}\n", true}                              => [["authenticated"], ["unresolved:#{deny}"]],
      {"\n  $this->denyAccessUnlessGranted('POST_EDIT', $post);\n", true}                                       => [["unresolved:POST_EDIT"]],
      {"\n  if ($x) { $this->denyAccessUnlessGranted('POST_EDIT', $post); }\n", true}                           => [["unresolved:$this->denyAccessUnlessGranted('POST_EDIT', $post)"]],
      {"\n  $this->denyAccessUnlessGranted(PostVoter::EDIT, $post);\n", true}                                   => [["unresolved:$this->denyAccessUnlessGranted(PostVoter::EDIT, $post)"]],
      {"\n  $this->denyAccessUnlessGranted('PUBLIC_ACCESS');\n", true}                                          => [] of Array(String),
      {"\n  // #{deny};\n", true}                                                                               => [] of Array(String),
      {"\n  if (!$this->isGranted('ROLE_ADMIN')) {\n    throw new AccessDeniedException();\n  }\n", true}       => [["role:ROLE_ADMIN"]],
      {"\n  if (!$this->isGranted('ROLE_ADMIN')) throw $this->createAccessDeniedException();\n", true}          => [["role:ROLE_ADMIN"]],
      {"\n  if ($this->isGranted('ROLE_ADMIN')) {\n    throw new AccessDeniedException();\n  }\n", true}        => [["authenticated"], ["unresolved:$this->isGranted('ROLE_ADMIN')"]],
      {"\n  if (!$this->isGranted('ROLE_ADMIN') && $x) {\n    throw new AccessDeniedException();\n  }\n", true} => [["authenticated"], ["unresolved:$this->isGranted('ROLE_ADMIN')"]],
      {"\n  $show = $this->isGranted('ROLE_ADMIN');\n", true}                                                   => [] of Array(String),
    }.each do |(body, own), expected|
      it "reads #{body.inspect} (#{own ? "own body" : "helper"})" do
        read(PhpAccess.symfony_refusals(body, own)).should eq(expected)
      end
    end
  end

  describe ".symfony_roles" do
    note = " (voter note)"
    {
      {["ROLE_ADMIN"], true}                                                          => [["role:ROLE_ADMIN"]],
      {["ROLE_ADMIN", "ROLE_EDITOR"], true}                                           => [["role:ROLE_ADMIN", "role:ROLE_EDITOR"]],
      {["ROLE_ADMIN", "ROLE_EDITOR"], false}                                          => [["authenticated"], ["unresolved:ROLE_ADMIN, ROLE_EDITOR"]],
      {["ROLE_USER", "@parts.read"], true}                                            => [["role:ROLE_USER", "unresolved:@parts.read"]],
      {["ROLE_USER", "@parts.read"], false}                                           => [["unresolved:ROLE_USER, @parts.read"]],
      {["ROLE_USER", "IS_AUTHENTICATED_FULLY"], true}                                 => [["role:ROLE_USER", "authenticated"]],
      {["@parts.read"], false}                                                        => [["unresolved:@parts.read"]],
      {["allow_if: is_granted('ROLE_ADMIN') and is_authenticated()"], true}           => [["role:ROLE_ADMIN"], ["authenticated"]],
      {["allow_if: is_granted(\"@api.access\") and is_authenticated()#{note}"], true} => [["unresolved:@api.access"], ["authenticated"]],
      {["@v", "allow_if: is_granted('@w')#{note}"], true}                             => [["unresolved:@v", "unresolved:@w"]],
    }.each do |(roles, affirmative), expected|
      it "reads #{roles} (#{affirmative ? "affirmative" : "other strategy"})" do
        read(PhpAccess.symfony_roles(roles, affirmative, note)).should eq(expected)
      end
    end
  end

  describe ".drupal_requirement" do
    {
      {"_permission", "administer nodes"}                => [["permission:administer nodes"]],
      {"_permission", "access content+administer nodes"} => [["permission:access content", "permission:administer nodes"]],
      {"_permission", "access content,administer nodes"} => [["permission:access content"], ["permission:administer nodes"]],
      {"_permission", "a+b,c"}                           => [["permission:a+b"], ["permission:c"]],
      {"_permission", "a,"}                              => [["permission:a"], ["unresolved:a,"]],
      {"_role", "administrator"}                         => [["role:administrator"]],
      {"_role", "editor+administrator"}                  => [["role:administrator", "role:editor"]],
      {"_role", "editor, administrator"}                 => [["role:editor"], ["role:administrator"]],
      {"_role", "authenticated"}                         => [["authenticated"]],
      {"_role", "anonymous"}                             => [["unresolved:anonymous"]],
      {"_role", " "}                                     => [["unresolved:_role:  "]],
      {"_entity_access", "node.update"}                  => [["unresolved:_entity_access: node.update"]],
      {"_custom_access", "\\Drupal\\x::access"}          => [["unresolved:_custom_access: \\Drupal\\x::access"]],
    }.each do |(key, value), expected|
      it "reads #{key}: #{value.inspect}" do
        read(PhpAccess.drupal_requirement(key, value)).should eq(expected)
      end
    end
  end

  describe ".wordpress_permission" do
    {
      "function () {\n  return current_user_can( 'edit_posts' );\n}"                                                                       => [["permission:edit_posts"]],
      "static function ( $request ) { return current_user_can(\"manage_options\"); }"                                                      => [["permission:manage_options"]],
      "fn () => current_user_can( 'edit_posts' )"                                                                                          => [["permission:edit_posts"]],
      "\n  return is_user_logged_in();\n"                                                                                                  => [["authenticated"]],
      "\n  if ( ! current_user_can( 'manage_options' ) ) {\n    return new WP_Error( 'rest_forbidden', 'Sorry.' );\n  }\n  return true;\n" => [["permission:manage_options"]],
      "\n  if ( ! is_user_logged_in() ) return false;\n  return true;\n"                                                                   => [["authenticated"]],
    }.each do |code, expected|
      it "reads #{code.inspect}" do
        PhpAccess.wordpress_permission(code).try { |cnf| read(cnf) }.should eq(expected)
      end
    end

    [
      "\n  return current_user_can( 'edit_post', $request['id'] );\n",
      "\n  return user_can( $user, 'edit_posts' );\n",
      "\n  if ( ! current_user_can( 'edit_posts' ) ) {\n    return true;\n  }\n  return true;\n",
      "\n  if ( 'edit' === $request['context'] && ! current_user_can( 'edit_posts' ) ) {\n    return new WP_Error( 'x' );\n  }\n  return true;\n",
      "\n  return current_user_can( 'edit_posts' ) || $public;\n",
      "\n  return ! is_user_logged_in();\n",
    ].each do |code|
      it "leaves #{code.inspect} unread" do
        PhpAccess.wordpress_permission(code).should be_nil
      end
    end
  end

  describe ".nextcloud" do
    {
      "#[NoAdminRequired]\n#[NoCSRFRequired]"               => [["authenticated"]],
      "/**\n * @NoAdminRequired\n */"                       => [["authenticated"]],
      ""                                                    => [["authenticated"], ["unresolved:admin (Nextcloud default)"]],
      "#[AuthorizedAdminSetting(settings: Admin::class)]"   => [["authenticated"], ["unresolved:AuthorizedAdminSetting"]],
      "#[NoAdminRequired]\n#[SubAdminRequired]"             => [["authenticated"], ["unresolved:SubAdminRequired"]],
      "#[NoAdminRequired]\n#[PasswordConfirmationRequired]" => [["authenticated"], ["unresolved:PasswordConfirmationRequired"]],
      "#[ExAppRequired]"                                    => [["unresolved:ExAppRequired"]],
      "#[AppApiAdminAccessWithoutUser]"                     => [["authenticated", "unresolved:AppApiAdminAccessWithoutUser"], ["unresolved:AppApiAdminAccessWithoutUser", "unresolved:admin (Nextcloud default)"]],
    }.each do |prelude, expected|
      it "reads #{prelude.inspect}" do
        read(PhpAccess.nextcloud(prelude)).should eq(expected)
      end
    end
  end

  describe ".yii_signed_in" do
    rule = ->(allow : Bool, actions : Array(String)?, roles : Array(String)?) { PhpAccess::YiiRule.new("rule", allow, actions, roles, true) }
    unread = PhpAccess::YiiRule.new("['allow' => true, 'matchCallback' => $f]", true, nil, nil, false)
    {
      "an allow for '@'"                       => {[rule.call(true, nil, ["@"])], [["authenticated"]]},
      "an allow for no roles"                  => {[rule.call(true, ["index"], nil)], [["authenticated"]]},
      "named roles, any one"                   => {[rule.call(true, nil, ["admin", "editor"])], [["role:admin", "role:editor"]]},
      "roles over two rules"                   => {[rule.call(true, nil, ["admin"]), rule.call(true, nil, ["editor"])], [["role:admin", "role:editor"]]},
      "a guest-only rule skipped"              => {[rule.call(true, nil, ["?"]), rule.call(true, nil, ["admin"])], [["role:admin"]]},
      "another action's rule skipped"          => {[rule.call(true, ["other"], ["@"]), rule.call(true, nil, ["admin"])], [["role:admin"]]},
      "no rule for a signed-in caller"         => {[rule.call(true, nil, ["?"])], [["deny"]]},
      "a deny for everyone first"              => {[rule.call(false, nil, ["@"]), rule.call(true, nil, ["admin"])], [["deny"]]},
      "an allow, then a deny for everyone"     => {[rule.call(true, nil, ["admin"]), rule.call(false, nil, nil)], [["role:admin"]]},
      "a deny for a named role, then an allow" => {[rule.call(false, nil, ["banned"]), rule.call(true, nil, ["@"])], [["authenticated"], ["unresolved:rule"]]},
      "an unread rule"                         => {[rule.call(true, nil, ["admin"]), unread], [["authenticated"], ["role:admin", "unresolved:#{unread.source}"]]},
      "an unread rule of another action"       => {[PhpAccess::YiiRule.new("x", true, ["other"], nil, false), rule.call(true, nil, ["@"])], [["authenticated"]]},
    }.each do |name, (rules, expected)|
      it "reads #{name}" do
        read(PhpAccess.yii_signed_in(rules, "index")).should eq(expected)
      end
    end
  end
end
