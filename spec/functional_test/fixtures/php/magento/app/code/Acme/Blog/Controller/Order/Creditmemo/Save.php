<?php

namespace Acme\Blog\Controller\Order\Creditmemo;

use Magento\Framework\App\Action\HttpPostActionInterface;
use Magento\Framework\Controller\Result\JsonFactory;

/**
 * Nested controller directory — Magento collapses Order/Creditmemo into a
 * single underscore-joined URL segment: /blog/order_creditmemo/save.
 */
class Save implements HttpPostActionInterface
{
    private $jsonFactory;

    public function __construct(JsonFactory $jsonFactory)
    {
        $this->jsonFactory = $jsonFactory;
    }

    public function execute()
    {
        return $this->jsonFactory->create();
    }
}
