<?php

// Reviewer regression: WP-CLI param extraction must be scoped to the
// specific method that is the registered command's callback (the one
// whose OWN signature is `($args, $assoc_args)`), never to the whole
// class body — an unrelated helper that happens to reuse `$args` as a
// local variable name must not pollute the command's param list.
WP_CLI::add_command('foo bar', 'Foo_Bar_Command');

class Foo_Bar_Command {
    function bar($args, $assoc_args) {
        $name = $args[0];
        $format = $assoc_args['format'];
    }

    // unrelated private helper, its own local var is also named $args
    private function build_report($args) {
        $summary = $args[7];
        return $summary;
    }
}
