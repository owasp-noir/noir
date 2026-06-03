package com.example.actions.orders;

import com.opensymphony.xwork2.ActionSupport;

public class OrdersController extends ActionSupport {
    private final OrdersService ordersService = new OrdersService();

    public String index() {
        ordersService.findAll();
        return SUCCESS;
    }

    public String show() {
        return SUCCESS;
    }

    public String create() {
        ordersService.save();
        return SUCCESS;
    }

    public String update() {
        return SUCCESS;
    }

    public String destroy() {
        ordersService.deleteById();
        return SUCCESS;
    }

    public String deleteConfirm() {
        return SUCCESS;
    }
}
