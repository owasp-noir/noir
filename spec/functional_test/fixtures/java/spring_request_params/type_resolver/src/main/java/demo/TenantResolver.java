package demo;

import org.springframework.core.MethodParameter;
import org.springframework.web.method.support.HandlerMethodArgumentResolver;

public class TenantResolver implements HandlerMethodArgumentResolver {
    @Override
    public boolean supportsParameter(MethodParameter parameter) {
        return parameter.hasParameterAnnotation(Tenant.class)
            && TenantRef.class.isAssignableFrom(parameter.getParameterType());
    }
}
