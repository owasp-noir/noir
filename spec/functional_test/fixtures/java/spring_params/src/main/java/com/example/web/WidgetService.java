package com.example.web;

import org.springframework.stereotype.Service;
import org.springframework.web.bind.annotation.*;

@Service
class WidgetService {
    @ResponseBody
    @PostMapping("/lookup")
    String lookup(Long widgetId, String label) { return "x"; }
}
