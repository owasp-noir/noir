package com.example.app.views;

import com.vaadin.flow.component.login.LoginOverlay;
import com.vaadin.flow.router.Route;
import com.vaadin.flow.server.auth.AnonymousAllowed;

@Route(value = "login", layout = MainLayout.class, absolute = true)
@AnonymousAllowed
public class LoginView extends LoginOverlay {}
