<?php
/**
 * Plugin Name: Demo
 */

class Demo_Settings_Controller extends WP_REST_Controller {
	public function __construct() {
		$this->namespace = 'wp/v2';
		$this->rest_base = 'settings';
	}

	public function register_routes() {
		register_rest_route(
			$this->namespace,
			'/' . $this->rest_base,
			array(
				array(
					'methods'             => WP_REST_Server::READABLE,
					'callback'            => array( $this, 'get_item' ),
					'permission_callback' => array( $this, 'get_item_permissions_check' ),
				),
				array(
					'methods'             => WP_REST_Server::CREATABLE,
					'callback'            => array( $this, 'create_item' ),
					'permission_callback' => '__return_true',
				),
			)
		);
	}

	public function get_item_permissions_check( $request ) {
		if ( ! current_user_can( 'manage_options' ) ) {
			return new WP_Error( 'rest_forbidden', 'Sorry.' );
		}
		return true;
	}
}

class Demo_Prop_Controller extends WP_REST_Controller {
	protected $namespace = 'demo/v1';
	protected $rest_base = 'items';

	public function register_routes() {
		register_rest_route( $this->namespace, '/' . $this->rest_base, array(
			'methods'             => 'POST',
			'callback'            => array( $this, 'create_item' ),
			'permission_callback' => function () {
				return current_user_can( 'edit_posts' );
			},
		) );
	}
}

// Inherits `$namespace` from the class above; its permission callback is
// `get_item_permissions_check`, which only another class of this file
// declares (its own comes from a parent elsewhere), so it is not read.
class Demo_Child_Controller extends Demo_Prop_Controller {
	protected $rest_base = 'children';

	public function register_routes() {
		register_rest_route( $this->namespace, '/' . $this->rest_base, array(
			'methods'             => 'GET',
			'callback'            => array( $this, 'get_items' ),
			'permission_callback' => array( $this, 'get_item_permissions_check' ),
		) );
		register_rest_route( $this->namespace, '/' . $this->rest_base . '/feed', array(
			'methods'             => 'GET',
			'callback'            => array( $this, 'get_items' ),
			'permission_callback' => array( $this, 'get_feed_permissions_check' ),
		) );
	}

	// WordPress core's read shape: the capability matters only in the edit
	// context; anyone else gets `true`.
	public function get_feed_permissions_check( $request ) {
		if ( 'edit' === $request['context'] && ! current_user_can( 'edit_posts' ) ) {
			return new WP_Error( 'rest_forbidden_context', 'Sorry.' );
		}
		return true;
	}
}

add_action( 'rest_api_init', function () {
	register_rest_route( 'demo/v1', '/me', array(
		'methods'             => 'GET',
		'callback'            => 'demo_me',
		'permission_callback' => 'demo_logged_in',
	) );
} );

function demo_logged_in() {
	return is_user_logged_in();
}

add_action( 'wp_ajax_demo_save', 'demo_save' );
add_action( 'wp_ajax_demo_lookup', 'demo_lookup' );
add_action( 'wp_ajax_nopriv_demo_lookup', 'demo_lookup' );
add_action( 'wp_ajax_demo_split', 'demo_split' );
