<?php

namespace Acme\Blog\Controller;

use Magento\Framework\App\ActionInterface;

/**
 * Shared base for blog controllers — not itself a routable action.
 */
abstract class AbstractPost implements ActionInterface
{
    abstract public function execute();

    protected function helper()
    {
        return true;
    }
}
