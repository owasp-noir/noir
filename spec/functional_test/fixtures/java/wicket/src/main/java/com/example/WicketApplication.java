package com.example;

import org.apache.wicket.Application;
import org.apache.wicket.protocol.http.WebApplication;
import org.apache.wicket.request.mapper.MountedMapper;
import org.apache.wicket.request.mapper.PackageMapper;
import org.apache.wicket.request.mapper.ResourceMapper;
import org.apache.wicket.request.resource.SharedResourceReference;

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
    }

    @Override
    public Class<UserListPage> getHomePage() {
        return UserListPage.class;
    }
}
