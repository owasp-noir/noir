package com.example.app.views;

import com.vaadin.flow.component.orderedlayout.VerticalLayout;
import com.vaadin.flow.router.Route;
import com.vaadin.flow.router.RouteAlias;
import jakarta.annotation.security.PermitAll;

@Route(value = "dashboard", layout = MainLayout.class)
@RouteAlias(value = "home", layout = MainLayout.class)
@PermitAll
public class DashboardView extends VerticalLayout {}
