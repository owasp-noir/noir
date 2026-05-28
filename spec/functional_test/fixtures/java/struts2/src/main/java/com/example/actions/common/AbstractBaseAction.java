package com.example.actions.common;

import com.opensymphony.xwork2.ActionSupport;

public abstract class AbstractBaseAction extends ActionSupport {
    public String execute() {
        return SUCCESS;
    }
}
