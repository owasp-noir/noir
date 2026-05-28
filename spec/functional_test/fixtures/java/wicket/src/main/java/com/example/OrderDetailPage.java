package com.example;

import org.apache.wicket.core.request.mapper.MountPath;
import org.apache.wicket.markup.html.WebPage;

@MountPath(value = "/orders/${orderId}", alt = {"/purchases/${orderId}"})
public class OrderDetailPage extends WebPage {
}
