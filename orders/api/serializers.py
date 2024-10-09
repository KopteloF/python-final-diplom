from rest_framework import serializers
from .models import *

class ContactSerializer(serializers.ModelSerializer):
    class Meta:
        model = Contact
        fields = "__all__"
        read_only_fields = ('id',)
        extra_kwargs = {
            'user': {'write_only': True}
        }


class UserSerializer(serializers.ModelSerializer):
    contacts = ContactSerializer(read_only=True, many=True)

    class Meta:
        model = User
        fields = "__all__"
        read_only_fields = ('id',)


class ShopSerializer(serializers.ModelSerializer):
    class Meta:
        model = Shop
        fields = "__all__"
        read_only_fields = ('id',)
        

class OrderItemAddSerializer(serializers.ModelSerializer):
    class Meta:
        model = OrderItem
        fields = "__all__"


class OrderItemSerializer(serializers.ModelSerializer):
    shop = serializers.StringRelatedField()
    category = serializers.StringRelatedField()

    class Meta:
        model = OrderItem
        fields = "__all__"
        read_only_fields = ('id',)
        extra_kwargs = {
            'order': {'write_only': True}
        }


class OrderModifySerializer(serializers.ModelSerializer):
    class Meta:
        model = Order
        fields = "__all__"
        read_only_fields = ('id',)


class OrderSerializer(serializers.ModelSerializer):
    ordered_items = OrderItemSerializer(read_only=True, many=True)

    total_sum = serializers.IntegerField()
    total_quantity = serializers.IntegerField()
    contact = ContactSerializer(read_only=True)

    class Meta:
        model = Order
        fields = "__all__"
        read_only_fields = ('id',)
        