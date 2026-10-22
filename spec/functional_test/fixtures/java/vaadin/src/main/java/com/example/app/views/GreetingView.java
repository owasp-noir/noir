package com.example.app.views;

import com.vaadin.flow.component.orderedlayout.VerticalLayout;
import com.vaadin.flow.router.Route;

@Route("greet/:name?/:id([0-9]+)")
public class GreetingView extends VerticalLayout {}
