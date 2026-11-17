require "../../spec_helper"
require "../../../src/analyzer/engines/java_engine"

private def supports(body : String) : String
  "class R implements HandlerMethodArgumentResolver {\n" \
  "    @Override\n" \
  "    public boolean supportsParameter(MethodParameter parameter) {\n" \
  "        #{body}\n" \
  "    }\n" \
  "    @Override\n" \
  "    public Object resolveArgument(MethodParameter parameter) { return null; }\n" \
  "}\n"
end

describe "Analyzer::Java::JavaEngine.resolver_supplied_types" do
  it "reads each spelling of a type test" do
    {
      "return ShopSession.class.isAssignableFrom(parameter.getParameterType());"             => ["ShopSession"],
      "return parameter.getParameterType().equals(ShopSession.class);"                       => ["ShopSession"],
      "return ShopSession.class.equals(param.getParameterType());"                           => ["ShopSession"],
      "return parameter.getParameterType() == com.example.ShopSession.class;"                => ["ShopSession"],
      "return ShopSession::class.java.isAssignableFrom(parameter.parameterType)"             => ["ShopSession"],
      "return parameter.parameterType == ShopSession::class.java"                            => ["ShopSession"],
      "return A.class.equals(p.getParameterType()) || B.class.equals(p.getParameterType());" => ["A", "B"],
    }.each do |body, expected|
      Analyzer::Java::JavaEngine.resolver_supplied_types(supports(body)).should eq(expected)
    end
  end

  it "reads a Kotlin expression body" do
    source = <<-KT
      class R : HandlerMethodArgumentResolver {
          override fun supportsParameter(parameter: MethodParameter): Boolean =
              Ledger::class.java.isAssignableFrom(parameter.parameterType)
          override fun resolveArgument(parameter: MethodParameter): Any? =
              if (parameter.parameterType == Long::class.java) 0L else Ledger()
      }
      KT
    Analyzer::Java::JavaEngine.resolver_supplied_types(source).should eq(["Ledger"])
  end

  it "accepts no type that only some arguments of it satisfy" do
    {
      "return parameter.hasParameterAnnotation(Tenant.class) && TenantRef.class.isAssignableFrom(parameter.getParameterType());",
      "return TenantRef.class.isAssignableFrom(parameter.getParameterType()) && parameter.getParameterName().equals(\"t\");",
      "return !TenantRef.class.isAssignableFrom(parameter.getParameterType());",
      "return parameter.getParameterType().isAssignableFrom(TenantRef.class);",
      "return parameter.hasParameterAnnotation(Tenant.class);",
    }.each do |body|
      Analyzer::Java::JavaEngine.resolver_supplied_types(supports(body)).should be_empty
    end
  end

  it "ignores type tests outside supportsParameter" do
    source = supports("return true;").sub("return null;", "return parameter.getParameterType() == Long.class ? 0L : null;")
    Analyzer::Java::JavaEngine.resolver_supplied_types(source).should be_empty
  end
end
