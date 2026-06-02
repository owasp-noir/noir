package com.demo

// Exercises action-extraction edge cases that must NOT leak helper methods
// as endpoints. Grails only dispatches to public, non-static controller
// methods, and never to JavaBean property accessors.
class ApiController {
    static allowedMethods = [save: 'POST']

    def index() {
        render 'ok'
    }

    def save() {
        render 'saved'
    }

    // Typed-return action (Grails 3+) — a real endpoint.
    List<String> list() {
        ['a', 'b']
    }

    // private helper — not an action.
    private def buildModel() {
        [:]
    }

    // protected typed helper — not an action.
    protected String formatBody() {
        'body'
    }

    // static helper — not an action.
    static int counter() {
        0
    }

    // JavaBean getter — a property accessor, not an action.
    String getDisplayName() {
        'demo'
    }
}
