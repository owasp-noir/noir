<?php

namespace Acme\Blog\Controller\Feed;

use Magento\Framework\App\Action\HttpGetActionInterface;
// Imported but NOT implemented — must not add POST to the emitted methods.
use Magento\Framework\App\Action\HttpPostActionInterface;
use Magento\Framework\Controller\Result\RawFactory;

class View implements HttpGetActionInterface
{
    private $rawFactory;

    public function __construct(RawFactory $rawFactory)
    {
        $this->rawFactory = $rawFactory;
    }

    public function execute()
    {
        return $this->rawFactory->create();
    }
}
