<?php
/**
 * Plugin Name: My Test Plugin
 * Description: A fixture plugin exercising WordPress AJAX and admin-post hooks.
 * Version: 1.0.0
 */

if (!defined('ABSPATH')) {
    exit;
}

// Authenticated + public admin-ajax handlers sharing one action.
add_action('wp_ajax_get_user_data', 'mtp_get_user_data');
add_action('wp_ajax_nopriv_get_user_data', 'mtp_get_user_data');

// Authenticated-only admin-ajax handler.
add_action('wp_ajax_save_settings', 'mtp_save_settings');

// admin-post.php handlers.
add_action('admin_post_export_csv', 'mtp_export_csv');
add_action('admin_post_nopriv_public_submit', 'mtp_public_submit');

function mtp_get_user_data() {
    $id = isset($_REQUEST['user']) ? intval($_REQUEST['user']) : 0;
    wp_send_json(array('id' => $id));
}

function mtp_save_settings() {
    update_option('mtp_settings', $_POST['settings']);
    wp_send_json_success();
}

function mtp_export_csv() {
    header('Content-Type: text/csv');
    echo "id,name\n";
    exit;
}

function mtp_public_submit() {
    wp_redirect(home_url('/thanks'));
    exit;
}
