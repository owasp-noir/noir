package com.example;

import org.apache.wicket.Application;
import org.apache.wicket.markup.html.WebPage;
import org.apache.wicket.protocol.http.WebApplication;
import org.apache.wicket.request.mapper.MountedMapper;
import org.apache.wicket.request.mapper.PackageMapper;
import org.apache.wicket.request.mapper.ResourceMapper;
import org.apache.wicket.request.resource.IResource;
import org.apache.wicket.request.resource.ResourceReference;
import org.apache.wicket.request.resource.SharedResourceReference;
import org.wicketstuff.rest.lambda.mounter.LambdaRestMounter;

public class WicketApplication extends WebApplication {
    private static final String DETAIL_PREFIX = "/users";

    @Override
    protected void init() {
        super.init();
        mountPage("/users", UserListPage.class);
        mountPage(DETAIL_PREFIX + "/${id}", UserDetailPage.class);
        mountPackage("/admin", AdminDashboardPage.class);
        mountResource("/assets/${name}", new SharedResourceReference("asset"));

        mount(new MountedMapper("/reports/${reportId}", ReportPage.class));
        mount(new PackageMapper("/legacy", LegacyPage.class));
        getRootRequestMapperAsCompound().add(new ResourceMapper("/downloads/#{file}", new SharedResourceReference("download")));

        mountAlias("/dashboards", AdminDashboardPage.class);
        mountResource("/api", new ResourceReference("rest") {
            private final PersonsRestResource resource = new PersonsRestResource();

            @Override
            public IResource getResource() {
                return resource;
            }
        });

        LambdaRestMounter restMounter = new LambdaRestMounter(this);
        restMounter.get("/lambda/status", attributes -> "ok", Object::toString);
        restMounter.post("/lambda/items/{itemId}", attributes -> "updated", Object::toString);
    }

    private void mountAlias(String mountPath, Class<? extends WebPage> pageClass) {
        getRootRequestMapperAsCompound().add(new MountedMapper(mountPath, pageClass));
    }

    @Override
    public Class<UserListPage> getHomePage() {
        return UserListPage.class;
    }
}
