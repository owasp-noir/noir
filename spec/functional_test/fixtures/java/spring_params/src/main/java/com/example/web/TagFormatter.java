package com.example.web;

import java.util.Locale;
import org.springframework.format.Formatter;

class TagFormatter implements Formatter<Tag> {
    public String print(Tag tag, Locale locale) { return tag.toString(); }
    public Tag parse(String text, Locale locale) { return new Tag(); }
}
