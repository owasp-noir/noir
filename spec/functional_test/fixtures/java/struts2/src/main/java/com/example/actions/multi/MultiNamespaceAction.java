package com.example.actions.multi;

import com.opensymphony.xwork2.ActionSupport;
import org.apache.struts2.convention.annotation.Namespace;
import org.apache.struts2.convention.annotation.Namespaces;

@Namespaces({
    @Namespace("/multi-a"),
    @Namespace("/multi-b")
})
public class MultiNamespaceAction extends ActionSupport {
    public String execute() {
        return SUCCESS;
    }
}
