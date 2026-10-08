# Composes the root types without importing graphene, and builds the schema
# through a project helper instead of `graphene.Schema(...)`.
from .catalog.schema import CatalogMutations, CatalogQueries
from .federation import build_federated_schema


class Query(CatalogQueries):
    pass


class Mutation(CatalogMutations):
    pass


schema = build_federated_schema(Query, mutation=Mutation)
