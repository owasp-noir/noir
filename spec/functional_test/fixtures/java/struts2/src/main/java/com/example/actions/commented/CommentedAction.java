package com.example.actions.commented;

import com.opensymphony.xwork2.ActionSupport;
import org.apache.struts2.convention.annotation.Action;
import org.apache.struts2.convention.annotation.Namespace;

// Comments after or between annotations must not detach them from the
// method or class they annotate.
@Namespace("/commented") // section root
public class CommentedAction extends ActionSupport {
    @Action("list") // note
    public String list() {
        return SUCCESS;
    }

    @Action("own")
    // own-line comment
    public String own() {
        return SUCCESS;
    }
}
