<?php
class My_REST_Controller extends WP_REST_Controller {
    const REST_NAMESPACE = 'myplugin/v2';
    protected $rest_base = 'books';

    public function register_routes() {
        $version   = '1';
        $namespace = 'vendor/v' . $version;
        $base      = 'route';
        register_rest_route( $namespace, '/' . $base, array(
            array(
                'methods'  => WP_REST_Server::READABLE,
                'callback' => array( $this, 'get_items' ),
            ),
            array(
                'methods'  => WP_REST_Server::CREATABLE,
                'callback' => array( $this, 'create_item' ),
            ),
        ) );
        register_rest_route( $namespace, '/' . $base . '/(?P<id>[\d]+)', array(
            'methods'  => WP_REST_Server::DELETABLE,
            'callback' => array( $this, 'delete_item' ),
        ) );
        register_rest_route( self::REST_NAMESPACE, '/settings', array(
            'methods'  => 'POST',
            'callback' => array( $this, 'update_settings' ),
        ) );
        register_rest_route( My_REST_Controller::REST_NAMESPACE, '/flags', array(
            'methods'  => 'GET',
            'callback' => array( $this, 'get_flags' ),
        ) );
        register_rest_route( 'myplugin/v4', "/{$this->rest_base}/(?P<id>[\d]+)", array(
            'methods'  => 'GET',
            'callback' => array( $this, 'get_item' ),
        ) );
        register_rest_route( "myplugin/v{$version}", "/$base/latest", array(
            'methods'  => 'GET',
            'callback' => array( $this, 'get_latest' ),
        ) );
    }

    public function register_more_routes() {
        // Assigned twice: no single value, so the route is skipped.
        $route = '/first';
        if ( is_admin() ) {
            $route = '/second';
        }
        register_rest_route( 'myplugin/v5', $route, array( 'methods' => 'GET', 'callback' => '__return_true' ) );
        // An interpolated name no scope defines: skipped, not emitted raw.
        register_rest_route( 'myplugin/v5', "/{$unknown}/x", array( 'methods' => 'GET', 'callback' => '__return_true' ) );
    }
}
