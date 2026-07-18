<?php
/**
 * REST API route registrations.
 */

add_action('rest_api_init', function () {
    register_rest_route('myplugin/v1', '/books', array(
        'methods'  => 'GET',
        'callback' => 'mtp_get_books',
    ));

    register_rest_route('myplugin/v1', '/books/(?P<id>\d+)', array(
        'methods'  => 'GET',
        'callback' => 'mtp_get_book',
    ));

    register_rest_route('myplugin/v1', '/books/(?P<id>\d+)', array(
        'methods'  => WP_REST_Server::EDITABLE,
        'callback' => 'mtp_update_book',
    ));

    register_rest_route('myplugin/v2', '/authors', array(
        'methods'  => array('GET', 'POST'),
        'callback' => 'mtp_handle_authors',
    ));

    register_rest_route('store/v1', '/checkout', array(
        'methods'  => WP_REST_Server::CREATABLE,
        'callback' => 'mtp_do_checkout',
    ));

    // Class-based controller with a dynamic namespace ($this->namespace).
    // Must be skipped rather than emitted as /wp-json/widgets/{id}/GET —
    // the namespace can't be resolved statically.
    register_rest_route($this->namespace, '/widgets/(?P<id>\d+)', array(
        'methods'  => 'GET',
        'callback' => array($this, 'get_widget'),
    ));

    // A named group with a nested alternation group — must normalize to
    // {type}, not leak a stray ')'.
    register_rest_route('myplugin/v1', '/items/(?P<type>(post|page))', array(
        'methods'  => 'GET',
        'callback' => 'mtp_items',
    ));

    // Optional non-capturing segment — the (?:...) and trailing ? artifacts
    // must be stripped from the emitted URL.
    register_rest_route('myplugin/v1', '/optional(?:/(?P<id>\d+))?', array(
        'methods'  => 'GET',
        'callback' => 'mtp_optional',
    ));

    // A commented-out method must NOT emit a phantom verb.
    register_rest_route('myplugin/v1', '/comments', array(
        // 'methods' => 'DELETE',
        'methods'  => 'GET',
        'callback' => 'mtp_comments',
    ));
});
