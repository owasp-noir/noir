class RouteMethod:
    DELETE = "delete"
    GET = "get"
    GET_LIST = "get_list"
    POST = "post"
    PUT = "put"
    INFO = "info"
    RELATED = "related"
    DISTINCT = "distinct"

    REST_MODEL_VIEW_CRUD_SET = {DELETE, GET, GET_LIST, POST, PUT, INFO}
