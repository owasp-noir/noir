package com.example.actions.admin;

import com.opensymphony.xwork2.ActionSupport;

// XML-configured handler for `<action name="dashboard"
// class="com.example.actions.admin.DashboardAction"/>` in
// admin-struts.xml. Exercises XML-action callee resolution: the default
// `execute` method is resolved from the XML `class` attribute and its
// 1-hop callees attached to the /admin/dashboard endpoint.
public class DashboardAction extends ActionSupport {
    private final DashboardService dashboardService = new DashboardService();

    public String execute() {
        dashboardService.loadStats();
        return SUCCESS;
    }
}
