import graphene


class CatalogQueries(graphene.ObjectType):
    product = graphene.Field(graphene.String, slug=graphene.String(required=True), doc_category="products")


class CatalogMutations(graphene.ObjectType):
    reindex_products = graphene.Boolean(force=graphene.Boolean())
