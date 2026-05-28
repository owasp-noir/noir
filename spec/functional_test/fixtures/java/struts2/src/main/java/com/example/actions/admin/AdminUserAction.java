package com.example.actions.admin;

import com.opensymphony.xwork2.ActionSupport;
import org.apache.struts2.convention.annotation.Action;
import org.apache.struts2.convention.annotation.Actions;
import org.apache.struts2.convention.annotation.Namespace;
import org.apache.struts2.convention.annotation.Result;

@Namespace("/admin")
public class AdminUserAction extends ActionSupport {
    @Action(value = "/user/list", results = {
        @Result(name = "success", location = "/user/list.jsp"),
        @Result(name = {"input", "error"}, location = "/user/list.jsp")
    })
    public String list() {
        return SUCCESS;
    }

    @Actions({
        @Action("users/create"),
        @Action(value = "users/save", results = @Result(name = "success", location = "/admin/users.jsp"))
    })
    public String save() {
        return SUCCESS;
    }
}
