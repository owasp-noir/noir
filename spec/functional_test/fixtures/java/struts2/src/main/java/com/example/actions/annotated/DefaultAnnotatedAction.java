package com.example.actions.annotated;

import com.opensymphony.xwork2.ActionSupport;
import org.apache.struts2.convention.annotation.Action;
import org.apache.struts2.convention.annotation.Namespace;
import org.apache.struts2.convention.annotation.Result;

@Namespace("/annotated")
@Action(results = {
    @Result(name = "success", location = "/WEB-INF/annotated.jsp")
})
public class DefaultAnnotatedAction extends ActionSupport {
    public String execute() {
        return SUCCESS;
    }
}
