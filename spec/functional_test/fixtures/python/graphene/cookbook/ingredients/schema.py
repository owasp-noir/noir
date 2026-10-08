import graphene
from graphene import relay
from graphene_django import DjangoObjectType
from graphene_django.filter import DjangoFilterConnectionField

from cookbook.ingredients.models import Category, Ingredient


class CategoryType(DjangoObjectType):
    class Meta:
        model = Category


class IngredientNode(DjangoObjectType):
    class Meta:
        model = Ingredient
        interfaces = (relay.Node,)
        filter_fields = ["name"]


class Query(graphene.ObjectType):
    category = graphene.Field(CategoryType, id=graphene.Int(), name=graphene.String())
    all_categories = graphene.List(CategoryType)
    all_ingredients = DjangoFilterConnectionField(IngredientNode)

    def resolve_all_categories(root, info):
        return Category.objects.all()


class CreateCategory(graphene.Mutation):
    class Arguments:
        name = graphene.String(required=True)
        parent_id = graphene.ID()

    category = graphene.Field(CategoryType)

    def mutate(root, info, name, parent_id=None):
        return CreateCategory(category=Category.objects.create(name=name))


class UpdateIngredient(relay.ClientIDMutation):
    class Input:
        name = graphene.String(required=True)

    ingredient = graphene.Field(IngredientNode)


class Mutation(graphene.ObjectType):
    create_category = CreateCategory.Field()
    update_ingredient = UpdateIngredient.Field()
