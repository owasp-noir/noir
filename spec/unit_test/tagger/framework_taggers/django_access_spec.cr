require "../../../spec_helper"
require "../../../../src/tagger/framework_taggers/python/django_access"

# Atoms as text, with an unresolved atom's fragment shown.
private def shown(cnf : Access::CNF) : Array(Array(String))
  cnf.map(&.map { |atom| atom.kind.unresolved? ? "unresolved:#{atom.value}" : atom.to_s }.sort!)
end

private def decorator(text : String) : Array(Array(String))?
  name, args, source = DjangoAccess.call(text).not_nil!
  DjangoAccess.decorator(name, args, source).try { |cnf| shown(cnf) }
end

describe DjangoAccess do
  describe ".decorator" do
    {
      "@login_required"                                               => [["authenticated"]],
      "@login_required(login_url='/accounts/login/')"                 => [["authenticated"]],
      "@permission_required('blog.add_post')"                         => [["authenticated"], ["permission:blog.add_post"]],
      "@permission_required('blog.add_post', raise_exception=True)"   => [["authenticated"], ["permission:blog.add_post"]],
      "@permission_required(perm='blog.add_post')"                    => [["authenticated"], ["permission:blog.add_post"]],
      "@permission_required(['blog.add_post', 'blog.change_post'])"   => [["authenticated"], ["permission:blog.add_post"], ["permission:blog.change_post"]],
      "@permission_required(('blog.add_post', BLOG_EDIT))"            => [["authenticated"], ["permission:blog.add_post"], ["unresolved:BLOG_EDIT"]],
      "@permission_required(PERMS)"                                   => [["authenticated"], ["unresolved:PERMS"]],
      "@permission_required(f'blog.{action}_post')"                   => [["authenticated"], ["unresolved:f'blog.{action}_post'"]],
      "@permission_required([])"                                      => [["unresolved:[]"]],
      "@permission_required(\n    'blog.add_post',\n)\ndef create():" => [["authenticated"], ["permission:blog.add_post"]],
      "@permission_required(\n    'blog.add_post',"                   => [["authenticated"], ["unresolved:permission_required("]],
      "@user_passes_test(lambda u: u.is_superuser)"                   => [["unresolved:user_passes_test(lambda u: u.is_superuser)"]],
      "@staff_member_required"                                        => [["authenticated"], ["unresolved:is_staff"]],
      "@decorators.login_required"                                    => [["authenticated"]],
    }.each do |text, expected|
      it "reads #{text.lines.first}" do
        decorator(text).should eq(expected)
      end
    end

    it "says nothing about a decorator that is not Django's" do
      decorator("@login_required_unless_debug").should be_nil
      decorator("@never_cache").should be_nil
    end
  end

  describe ".drf" do
    {
      "[IsAuthenticated]"                                       => [["authenticated"]],
      "(IsAuthenticated,)"                                      => [["authenticated"]],
      "[AllowAny]"                                              => [] of Array(String),
      "[IsAdminUser]"                                           => [["authenticated"], ["unresolved:is_staff"]],
      "[IsAuthenticated, IsOwner]"                              => [["authenticated"], ["unresolved:IsOwner"]],
      "[IsAuthenticated | IsAdminUser]"                         => [["authenticated"], ["authenticated", "unresolved:is_staff"]],
      "[IsAuthenticated & IsOwner]"                             => [["authenticated"], ["unresolved:IsOwner"]],
      "[~IsOwner]"                                              => [["unresolved:~IsOwner"]],
      "[IsAuthenticated, ~(IsOwner | IsAdminUser)]"             => [["authenticated"], ["unresolved:~(IsOwner | IsAdminUser)"]],
      "[permissions.IsAuthenticated]"                           => [["authenticated"]],
      "['rest_framework.permissions.IsAuthenticated']"          => [["authenticated"]],
      "[TokenHasScope]"                                         => [["unresolved:TokenHasScope"]],
      "[HasScope('read')]"                                      => [["unresolved:HasScope('read')"]],
      "[DjangoModelPermissions]"                                => [["authenticated"], ["unresolved:DjangoModelPermissions"]],
      "[IsAuthenticated, perms[0]]"                             => [["unresolved:[IsAuthenticated, perms[0]]"]],
      "[IsAuthenticated |]"                                     => [["unresolved:[IsAuthenticated |]"]],
      "[(IsAuthenticated | IsOwner) & (IsAdminUser | IsOwner)]" => [["authenticated", "unresolved:IsOwner"], ["authenticated", "unresolved:IsOwner"], ["unresolved:IsOwner", "unresolved:is_staff"]],
    }.each do |text, expected|
      it "reads #{text}" do
        shown(DjangoAccess.drf(text, "POST")).sort.should eq(expected.sort)
      end
    end

    it "opens a read-only class to safe verbs and keeps an unknown verb unread" do
      shown(DjangoAccess.drf("[IsAuthenticatedOrReadOnly]", "GET")).should be_empty
      shown(DjangoAccess.drf("[IsAuthenticatedOrReadOnly]", "DELETE")).should eq([["authenticated"]])
      shown(DjangoAccess.drf("[IsAuthenticatedOrReadOnly]", "ANY")).should eq([["unresolved:IsAuthenticatedOrReadOnly"]])
      shown(DjangoAccess.drf("[DjangoModelPermissionsOrAnonReadOnly]", "HEAD")).should be_empty
      shown(DjangoAccess.drf("[DjangoModelPermissionsOrAnonReadOnly]", "PUT")).should eq([["authenticated"], ["unresolved:DjangoModelPermissionsOrAnonReadOnly"]])
    end
  end

  describe ".method_decorator_targets" do
    it "lists the decorators of a single or list argument" do
      DjangoAccess.method_decorator_targets("login_required, name='dispatch'").should eq(["login_required"])
      DjangoAccess.method_decorator_targets("[never_cache, permission_required('a.b')], name='get'").should eq(["never_cache", "permission_required('a.b')"])
    end
  end
end
