package com.example.app.views;

import com.vaadin.flow.component.orderedlayout.VerticalLayout;
import com.vaadin.flow.router.Route;

@Route(value = SettingsView.ROUTE, // settings page
    layout = MainLayout.class)
public class SettingsView extends VerticalLayout {
  static final String ROUTE = "settings";
}
