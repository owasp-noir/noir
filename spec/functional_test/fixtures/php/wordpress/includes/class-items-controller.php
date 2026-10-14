<?php
// A WP_REST_Controller registers its routes from `$this->namespace` and
// `'/' . $this->rest_base` concatenations.
class Items_REST_Controller extends WP_REST_Controller {
    protected $namespace = 'itemsplugin/v2';
    protected $rest_base = 'items';

    public function register_routes() {
        register_rest_route( $this->namespace, '/' . $this->rest_base, array(
            array(
                'methods'             => WP_REST_Server::READABLE,
                'callback'            => array( $this, 'get_items' ),
                'permission_callback' => array( $this, 'get_items_permissions_check' ),
                'args'                => array(
                    'per_page' => array( 'type' => 'integer' ),
                ),
            ),
            array(
                'methods'  => WP_REST_Server::CREATABLE,
                'callback' => array( $this, 'create_item' ),
                'args'     => array(
                    'title' => array( 'required' => true ),
                ),
            ),
        ) );
        register_rest_route( $this->namespace, '/' . $this->rest_base . '/(?P<id>[\d]+)', array(
            array(
                'methods'  => WP_REST_Server::DELETABLE,
                'callback' => array( $this, 'delete_item' ),
            ),
        ) );
    }
}
