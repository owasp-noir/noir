package com.acme.q;

import org.jboss.resteasy.reactive.RestHeader;
import org.jboss.resteasy.reactive.RestQuery;

public class Params {
    @RestQuery String filter;
    @RestHeader("X-Bean-H") String beanHeader;
    @RestQuery("page_no") int page;
}
