package com.example;

import org.apache.wicket.markup.html.panel.Panel;
import org.apache.wicket.markup.html.link.BookmarkablePageLink;

public class NavigationPanel extends Panel {
    public NavigationPanel(String id) {
        super(id);
        add(new BookmarkablePageLink<>("products", ProductPage.class));
        add(new BookmarkablePageLink<>("user", UserDetailPage.class));
    }

    public void goToOrder() {
        setResponsePage(OrderDetailPage.class);
    }
}
