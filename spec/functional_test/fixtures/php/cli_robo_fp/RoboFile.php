<?php

use Robo\Tasks;

// Reviewer regression: the `@command` docblock tag must bind ONLY to the
// very next method signature. It must never stay sticky for the rest of
// the file, so it must not attach to a preceding constructor or to a
// later untagged helper method.
class RoboFile extends Tasks
{
    public function __construct($container)
    {
        $this->container = $container;
    }

    /**
     * @command foo:bar
     */
    public function fooBar($arg)
    {
        return $this->formatOutput($arg, 'prefix:');
    }

    // Not a Robo command, just a private helper used by fooBar. Its
    // params must never leak into foo:bar's param list.
    protected function formatOutput($text, $prefix)
    {
        return $prefix . $text;
    }
}
