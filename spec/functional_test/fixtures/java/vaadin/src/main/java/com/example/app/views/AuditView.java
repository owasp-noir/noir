package com.example.app.views;

import com.vaadin.flow.component.orderedlayout.VerticalLayout;
import com.vaadin.flow.router.Route;

// A fully-qualified layout class still picks up its @RoutePrefix.
@Route(value = "audit", layout = com.example.app.views.MainLayout.class)
public class AuditView extends VerticalLayout {}
