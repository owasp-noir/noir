<?php
/**
 * Plugin Name: Route Constants
 */
define( 'MYPLUGIN_REST_NS', 'myplugin/v3' );
const MYPLUGIN_LEGACY_NS = 'myplugin/legacy';
require_once __DIR__ . '/includes/class-my-rest-controller.php';
add_action( 'rest_api_init', function () {
    ( new My_REST_Controller() )->register_routes();
    register_rest_route( 'control/v1', '/ping', array( 'methods' => 'GET', 'callback' => '__return_true' ) );
    register_rest_route( MYPLUGIN_REST_NS, '/status', array( 'methods' => 'GET', 'callback' => '__return_true' ) );
    register_rest_route( MYPLUGIN_LEGACY_NS, '/status', array( 'methods' => 'GET', 'callback' => '__return_true' ) );
    // Defined in no file of the scan: skipped.
    register_rest_route( OTHER_PLUGIN_NS, '/unknown', array( 'methods' => 'GET', 'callback' => '__return_true' ) );
} );
