from tracker.decorators import detail_route


class VotedResourceMixin:
    @detail_route(methods=["POST"])
    def upvote(self, request, pk=None):
        return None
