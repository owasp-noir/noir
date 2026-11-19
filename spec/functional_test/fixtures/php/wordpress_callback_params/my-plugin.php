<?php
/**
 * Plugin Name: Callback Params
 */
add_action( 'rest_api_init', function () {
    register_rest_route( 'myplugin/v1', '/control/(?P<id>\d+)', array(
        'methods'  => 'GET',
        'callback' => 'myplugin_control',
        'args'     => array( 'declared' => array( 'required' => true ) ),
    ) );
    register_rest_route( 'myplugin/v1', '/orders', array(
        'methods'  => 'POST',
        'callback' => 'myplugin_create_order',
    ) );
    register_rest_route( 'myplugin/v1', '/search', array(
        'methods'  => 'GET',
        'callback' => function ( $req ) {
            return array( $req->get_param( 'q' ), $req['page'] );
        },
    ) );
} );

function myplugin_control( WP_REST_Request $request ) {
    return rest_ensure_response( array() );
}

function myplugin_create_order( WP_REST_Request $request ) {
    $sku    = $request->get_param( 'sku' );
    $qty    = $request['qty'];
    $token  = $request->get_header( 'X-Shop-Token' );
    $upload = $request->get_file_params()['receipt'];
    return rest_ensure_response( array( $sku, $qty ) );
}

add_action( 'wp_ajax_myplugin_save', 'myplugin_save' );
add_action( 'wp_ajax_nopriv_myplugin_lookup', 'myplugin_lookup' );
add_action( 'wp_ajax_myplugin_lookup', 'myplugin_lookup' );
add_action( 'admin_post_myplugin_export', function () {
    $format = filter_input( INPUT_GET, 'format' );
    $theme  = $_COOKIE['theme'];
} );

function myplugin_save() {
    check_ajax_referer( 'myplugin', 'nonce' );
    update_option( 'myplugin_title', sanitize_text_field( $_POST['title'] ) );
    wp_send_json_success();
}

function myplugin_lookup() {
    $term = isset( $_GET['term'] ) ? $_GET['term'] : '';
    $id   = absint( $_REQUEST['post_id'] );
    wp_send_json( array( $term, $id ) );
}

class Myplugin_Admin {
    public function __construct() {
        add_action( 'wp_ajax_myplugin_upload', array( $this, 'upload' ) );
    }

    public function upload() {
        $file = $_FILES['attachment'];
        $ua   = $_SERVER['HTTP_USER_AGENT'];
    }
}
