package com.example.app.views;

import com.vaadin.flow.component.orderedlayout.VerticalLayout;
import com.vaadin.flow.router.BeforeEvent;
import com.vaadin.flow.router.HasUrlParameter;
import com.vaadin.flow.router.Route;

@Route("product")
public class ProductView extends VerticalLayout implements HasUrlParameter<Long> {
  @Override
  public void setParameter(BeforeEvent event, Long parameter) {}
}
