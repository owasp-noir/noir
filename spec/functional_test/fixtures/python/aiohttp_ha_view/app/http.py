from aiohttp import web


class HomeAssistantView:
    url: str | None = None
    extra_urls: list[str] = []
    requires_auth = True

    def register(self, app: web.Application, router: web.UrlDispatcher) -> None:
        urls = [self.url, *self.extra_urls]
        for method in ("get", "post", "delete", "put", "patch", "head", "options"):
            if not (handler := getattr(self, method, None)):
                continue
            for url in urls:
                router.add_route(method, url, handler)
