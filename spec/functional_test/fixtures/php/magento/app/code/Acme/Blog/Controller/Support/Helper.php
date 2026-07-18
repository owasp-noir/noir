<?php

namespace Acme\Blog\Controller\Support;

/**
 * A non-action helper under /Controller/. It has no execute() method
 * (only executeInternal), so it must NOT emit an endpoint.
 */
class Helper
{
    public function executeInternal()
    {
        return true;
    }
}
