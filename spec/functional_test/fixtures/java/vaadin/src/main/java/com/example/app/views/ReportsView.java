package com.example.app.views;

import com.vaadin.flow.component.orderedlayout.VerticalLayout;
import com.vaadin.flow.router.Route;
import jakarta.annotation.security.RolesAllowed;

@Route
@RolesAllowed("ADMIN")
public class ReportsView extends VerticalLayout {}
