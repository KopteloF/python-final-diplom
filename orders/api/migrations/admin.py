from django.contrib import admin
from .models import *


# Register your models here.

@admin.register(User)
class UserAdmin(admin.ModelAdmin):
    list_display = ['id', 'email', 'company', 'position', 'type']
    search_fields = ('email',)


@admin.register(Contact)
class ContactAdmin(admin.ModelAdmin):
    list_display = ['id', 'user', 'city', 'street', 'house', 'structure', 'building', 'apartment', 'phone']


@admin.register(ConfirmEmailToken)
class ConfirmEmailTokenAdmin(admin.ModelAdmin):
    list_display = ['user', 'created_at', 'key']


@admin.register(Order)
class OrderAdmin(admin.ModelAdmin):
    list_display = ['id', 'user', 'status', 'contact', 'created', 'updated']
    search_fields = ('status',)


@admin.register(OrderItem)
class OrderItemAdmin(admin.ModelAdmin):
    list_display = ['id', 'order', 'category', 'shop', 'product_name', 'external_id', 'quantity', 'price',
                    'total_amount']
    search_fields = ('order',)


admin.site.site_title = 'Админ-панель Сервис заказа товаров для розничных сетей'
admin.site.site_header = 'Админ-панель Сервис заказа товаров для розничных сетей'