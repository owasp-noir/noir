import graphene
from graphene_django import DjangoObjectType

from cookbook.recipes.models import Recipe


class RecipeType(DjangoObjectType):
    class Meta:
        model = Recipe


class Query(graphene.ObjectType):
    recipe = graphene.Field(
        RecipeType,
        recipe_id=graphene.ID(required=True),
        args={"include_drafts": graphene.Boolean()},
        description="One recipe",
    )
    all_recipes = graphene.List(graphene.NonNull(RecipeType), first=graphene.Int())
    hello = graphene.String(name=graphene.String(default_value="stranger"))


class Unused(graphene.ObjectType):
    never_bound = graphene.String(flag=graphene.Boolean())
