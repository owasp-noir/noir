require "../../../models/detector"

module Detector::Php
  class Wordpress < Detector
    detector_for "php_wordpress", extensions: %w[.php .phtml], basenames: %w[composer.json]

    # Strong, WordPress-specific source markers. A generic PHP file that
    # merely calls `add_action` is not enough — we require a marker that
    # is effectively unique to WordPress core/plugin/theme code so we do
    # not light up on every PHP project.
    WP_SOURCE_MARKERS = [
      "register_rest_route",
      "WP_REST_Server",
      "WP_REST_Controller",
      "add_shortcode",
      "register_activation_hook",
      "register_deactivation_hook",
      "wp_enqueue_script",
      "wp_enqueue_style",
      "add_menu_page",
      "add_submenu_page",
      "get_template_directory",
      "wp_insert_post",
      "wp_get_current_user",
    ]

    # WordPress core bootstrap files. Their presence is unambiguous.
    WP_CORE_FILES = [
      "wp-config.php",
      "wp-load.php",
      "wp-settings.php",
      "wp-blog-header.php",
      "wp-cron.php",
    ]

    def detect(filename : String, file_contents : String) : Bool
      # composer.json referencing a WordPress distribution / packagist mirror
      if filename.ends_with?("composer.json") &&
         (file_contents.includes?("johnpbloch/wordpress") ||
         file_contents.includes?("roots/wordpress") ||
         file_contents.includes?("wpackagist-plugin/") ||
         file_contents.includes?("wpackagist-theme/") ||
         file_contents.includes?("\"type\": \"wordpress-plugin\"") ||
         file_contents.includes?("\"type\": \"wordpress-theme\""))
        return true
      end

      # WordPress core bootstrap files
      base = File.basename(filename)
      if WP_CORE_FILES.includes?(base)
        return true
      end

      # Core directory layout, matched on the scan-base-relative path so
      # the leading `/` covers a repo-root `wp-content/` too. On the
      # absolute path a checkout that merely lived under a `wp-content/`
      # directory made every `.php` file in it look like WordPress.
      if filename.ends_with?(".php")
        relative = base_relative_path(filename)
        if relative.includes?("/wp-content/") ||
           relative.includes?("/wp-includes/") ||
           relative.includes?("/wp-admin/")
          return true
        end
      end

      # Plugin / theme file headers (`Plugin Name:` / `Theme Name:` in the
      # leading docblock) are the canonical WordPress metadata markers.
      if filename.ends_with?(".php") &&
         (file_contents.includes?("Plugin Name:") || file_contents.includes?("Theme Name:"))
        return true
      end

      # Strong WordPress source markers inside PHP files.
      if filename.ends_with?(".php")
        return true if WP_SOURCE_MARKERS.any? { |marker| file_contents.includes?(marker) }

        # Hook-name prefixes (`wp_ajax_`, `admin_post_`) are only
        # WordPress-specific inside an add_action() call — a bare
        # `admin_post_` substring also occurs in Symfony/Laravel route
        # names like `admin_post_edit`, so anchor to the call syntax
        # rather than matching the prefix anywhere in the file.
        return true if content_matches?(file_contents, /add_action\s*\(\s*['"](?:wp_ajax_|admin_post_)/)
      end

      false
    end
  end
end
