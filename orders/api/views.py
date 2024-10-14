from django.core.validators import URLValidator
from django.core.exceptions import ValidationError
from django.contrib.auth.password_validation import validate_password
from django.contrib.auth import authenticate
from django.db import IntegrityError
from django.db.models import Sum, Q, Prefetch
from django.core.mail import EmailMessage
from requests import get
from rest_framework import status, generics, viewsets
from rest_framework.response import Response
from rest_framework.pagination import PageNumberPagination
from rest_framework.views import APIView
from rest_framework.permissions import IsAuthenticated
from rest_framework.authtoken.models import Token
from .models import *
from .serializers import *
from yaml import load as load_yaml, Loader
from ujson import loads as load_json


# Create your views here.

def on_change_order_status(user_id, order_id):
    """Функция отправит пользователю письмо об изменении статуса заказа"""
    
    user = User.objects.get(id=user_id)
    order = Order.objects.get(id=order_id)
    message = 'Твой заказ номер {} имеет статус "{}"'.format(
        order_id,
        order.status.upper())
    to_email = user.email
    mail_subject = 'Статус заказа изменен'
    email = EmailMessage(mail_subject, message, to=[to_email])
    email.send()


class ApiListPagination(PageNumberPagination):
    page_size = 3
    page_size_query_param = 'page_size'
    max_page_size = 10000


class RegisterUser(APIView):
    """Класс для регистрации покупателя"""
    throttle_scope = 'register'

    def post(self, request, *args, **kwargs):
        if {'first_name', 'last_name', 'email', 'password', 'company', 'position'}.issubset(request.data):
            try:
                validate_password(request.data['password'])
            except Exception as error:
                return Response({'status': False, 'error': {'password': error}}, status=status.HTTP_403_FORBIDDEN)
            else:
                user_serializer = UserSerializer(data=request.data)
                if user_serializer.is_valid():
                    user = user_serializer.save()
                    user.set_password(request.data['password'])
                    user.save()
                    token, _ = ConfirmEmailToken.objects.get_or_create(user_id=user.id)
                    return Response({'status': True, 'token for confirm email': token.key})
                else:
                    return Response({'status': False, 'error': user_serializer.errors}, status=status.HTTP_403_FORBIDDEN
                                    )

        return Response({'status': False, 'error': 'Не указаны все поля'}, status=status.HTTP_400_BAD_REQUEST)


class Сonfirmation(APIView):
    """Класс для подтверждения регистрации""" 
    def post(self, request, *args, **kwargs):
        if {'email', 'token'}.issubset(request.data):
            token = ConfirmEmailToken.objects.filter(user__email=request.data['email'],
                                                     key=request.data['token']).first()
            if token:
                token.user.is_active = True
                token.user.save()
                token.delete()
                return Response({
                    'Status': True
                })
            else:
                return Response({'Status': False, 'Errors': 'Неправильно указан token или email'})
        return Response({'Status': False, 'Errors': 'Не указыны все аргументы'}) 


class LoginUser(APIView):
    """Класс для входа(авторизации)"""
    def post(self, request, *args, **kwargs):
        if {'email', 'password'}.issubset(request.data):
            user = authenticate(request, username=request.data['email'], password=request.data['password'])
            if user is not None:
                if user.is_active:
                    token, _ = Token.objects.get_or_create(user=user)
                    return Response({'status': True, 'token': token.key})
            return Response({'status': False, 'error': 'Ошибка входа'}, status=status.HTTP_403_FORBIDDEN)
        return Response({'status': False, 'error': 'Не указаны все поля'}, status=status.HTTP_400_BAD_REQUEST)


class DetailUser(APIView):
    """Класс для просмотра и изменения данных пользователя"""
    permission_classes = [IsAuthenticated]

    def get(self, request, *args, **kwargs):
        serializer = UserSerializer(request.user)
        return Response(serializer.data)

    def post(self, request, *args, **kwargs):
        if {'password'}.issubset(request.data):
            if 'password' in request.data:
                try:
                    validate_password(request.data['password'])
                except Exception as error:
                    return Response({'status': False, 'error': {'password': error}}, status=status.HTTP_400_BAD_REQUEST)
                else:
                    request.user.set_password(request.data['password'])
            user_serializer = UserSerializer(request.user, data=request.data, partial=True)
            if user_serializer.is_valid():
                user_serializer.save()
                return Response({'status': True}, status=status.HTTP_200_OK)
            else:
                return Response(
                    {'status': False, 'Errors': 'Не указаны все арументы'})


class UserViewSet(viewsets.ModelViewSet):
    queryset = User.objects.all()
    serializer_class = UserSerializer


class ContactView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, *args, **kwargs):
        """Функция получения контактных данных"""
        contact = Contact.objects.filter(user_id=request.user.id)
        serializer = ContactSerializer(contact, many=True)
        return Response(serializer.data)

    def put(self, request, *args, **kwargs):
        """Метод изменения контакта"""
        if {'id'}.issubset(request.data):
            try:
                contact = Contact.objects.get(pk=int(request.data['id']))
            except ValueError:
                return Response({'status': False, 'error': 'Не верный тип поля ID'}, status=status.HTTP_400_BAD_REQUEST)
            serializer = ContactSerializer(contact, data=request.data, partial=True)
            if serializer.is_valid():
                serializer.save()
                return Response({'status': True}, status=status.HTTP_200_OK)
            return Response({'status': False, 'error': serializer.errors}, status=status.HTTP_400_BAD_REQUEST)
        return Response({'status': False, 'error': 'Не указаны необходимые поля'}, status=status.HTTP_400_BAD_REQUEST)

    def delete(self, request, *args, **kwargs):
        """Функция удаления контакта"""
        if {'items'}.issubset(request.data):
            for item in request.data["items"].split(','):
                try:
                    contact = Contact.objects.get(pk=int(item))
                    contact.delete()
                except ValueError:
                    return Response({'status': False, 'error': 'Не верный тип поля'}, status=status.HTTP_400_BAD_REQUEST
                                    )
            return Response({'status': True}, status=status.HTTP_204_NO_CONTENT)
        return Response({'status': False, 'error': 'Не указаны ID контактов'}, status=status.HTTP_400_BAD_REQUEST)


class ContactAPIList(generics.ListCreateAPIView):
    queryset = Contact.objects.all()
    serializer_class = ContactSerializer


class PartnerUpdate(APIView):
    """
    Класс для обновления прайса от поставщика
    """
    permission_classes = [IsAuthenticated]
    throttle_scope = 'change_price'

    def post(self, request, *args, **kwargs):
        if request.user.type != 'shop':
            return Response({'status': False, 'error': 'Только для магазинов'}, status=status.HTTP_403_FORBIDDEN)

        url = request.data.get('url')
        if url:
            validate_url = URLValidator()
            try:
                validate_url(url)
            except ValidationError as e:
                return Response({'status': False, 'error': str(e)}, status=status.HTTP_400_BAD_REQUEST)
            else:
                stream = get(url).content
                data = load_yaml(stream, Loader=Loader)
                shop, _ = Shop.objects.get_or_create(user_id=request.user.id, defaults={
                    'name': data['shop'], 'url': url})
                if shop.name != data['shop']:
                    return Response({'status': False, 'error': 'В файле некоректное навание магазина'},
                                    status=status.HTTP_400_BAD_REQUEST)
                return Response({'status': True})
        return Response({'status': False, 'error': 'Не указаны все необходимые поля'},
                        status=status.HTTP_400_BAD_REQUEST)


class PartnerState(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, *args, **kwargs):
        """Функция для получения статуса магазина"""
        if request.user.type != 'shop':
            return Response({'status': False, 'error': 'Только для магазинов'}, status=status.HTTP_403_FORBIDDEN)
        shop = request.user.shop
        serializer = ShopSerializer(shop)
        return Response(serializer.data)

    def post(self, request, *args, **kwargs):
        """Функция изменения статуса магазина"""
        if request.user.type != 'shop':
            return Response({'status': False, 'error': 'Только для магазинов'}, status=status.HTTP_403_FORBIDDEN)
        state = request.data.get('state')
        if state:
            try:
                Shop.objects.filter(user_id=request.user.id)
                return Response({'status': True})
            except ValueError as error:
                return Response({'status': False, 'error': str(error)}, status=status.HTTP_400_BAD_REQUEST)
        return Response({'status': False, 'error': 'Не указано поле Статус'}, status=status.HTTP_400_BAD_REQUEST)


class PartnerOrders(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, *args, **kwargs):
        """Функция для получения заказов поставщиками"""
        if request.user.type != 'shop':
            return Response({'status': False, 'error': 'Только для магазинов'}, status=status.HTTP_403_FORBIDDEN)
        prefetch = Prefetch('ordered_items', queryset=OrderItem.objects.filter(
            shop__user_id=request.user.id))
        order = Order.objects.filter(
            ordered_items__shop__user_id=request.user.id).exclude(status='cart')\
            .prefetch_related(prefetch).select_related('contact').annotate(
                    total_sum=Sum('ordered_items__total_amount'),
                    total_quantity=Sum('ordered_items__quantity'))
        serializer = OrderSerializer(order, many=True)
        return Response(serializer.data)


class ShopView(generics.ListAPIView):
    """ Класс просмотра списка магазинов"""
    queryset = Shop.objects.filter(state=True)
    serializer_class = ShopSerializer


class CategoryView(generics.ListCreateAPIView):
    """ Класс просмотра списка категорий"""
    queryset = Category.objects.all()
    serializer_class = CategorySerializer


class ProductView(APIView):
    """ Класс просмотра списка товаров"""

    pagination_class = ApiListPagination

    def get(self, request, *args, **kwargs):
        query = Q(shop__state=True)
        shop_id = request.query_params.get('shop_id')
        category_id = request.query_params.get('category_id')
        if shop_id:
            query = query & Q(shop_id=shop_id)
        if category_id:
            query = query & Q(category_id=category_id)
        queryset = Product.objects.filter(query).select_related('shop', 'category').\
            prefetch_related('product_parameters').distinct()
        serializer = ProductSerializer(queryset, many=True)
        return Response(serializer.data)

class ProductViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = Product.objects.all()
    serializer_class = ProductSerializer


class CartView(APIView):
    """Класс корзины покупателей"""
    permission_classes = [IsAuthenticated]

    def get(self, request, *args, **kwargs):
        """Функция для получения содержимого корзины"""
        cart = Order.objects.filter(
            user_id=request.user.id, status='cart'
        ).prefetch_related('ordered_items').annotate(
            total_sum=Sum('ordered_items__total_amount'),
            total_quantity=Sum('ordered_items__quantity')
        )
        serializer = OrderSerializer(cart, many=True)
        return Response(serializer.data)

    def post(self, request, *args, **kwargs):
        '''
        Функция для добавление товаров в корзину
        '''
        items = request.data.get('items')
        if items:
            try:
                items_dict = load_json(items)
            except ValueError:
                Response({'Status': False, 'Errors': 'Неверный формат запроса'})
            else:
                cart, _ = Order.objects.get_or_create(user_id=request.user.id, status='cart')
                objects_created = 0
                for order_item in items_dict:
                    order_item.update({'order': cart.id})
                    product = Product.objects.filter(external_id=order_item['external_id']).values('category', 'shop',
                                                                                                   'name', 'price')
                    order_item.update({'category': product[0]['category'], 'shop': product[0]['shop'],
                                       'product_name': product[0]['name'], 'price': product[0]['price']})
                    serializer = OrderItemAddSerializer(data=order_item)
                    if serializer.is_valid():
                        try:
                            serializer.save()
                        except IntegrityError as error:
                            return Response({'status': False, 'errors': str(error)},
                                            status=status.HTTP_400_BAD_REQUEST)
                        else:
                            objects_created += 1
                    else:
                        return Response({'status': False, 'error': serializer.errors},
                                        status=status.HTTP_400_BAD_REQUEST)
                return Response({'status': True, 'num_objects': objects_created})

        return Response({'status': False, 'error': 'Не указаны необходимые поля'},
                        status=status.HTTP_400_BAD_REQUEST)

    def put(self, request, *args, **kwargs):
        """Функция для изменения количества товара в корзине"""
        items = request.data.get('items')
        if items:
            try:
                items_dictionary = load_json(items)
            except ValueError:
                Response({'Status': False, 'Errors': 'Неверный формат запроса'})
            else:
                cart, _ = Order.objects.get_or_create(user_id=request.user.id, status='cart')
                objects_updated = 0
                for item in items_dictionary:
                    if isinstance(item['id'], int) and isinstance(item['quantity'], int):
                        objects_updated += OrderItem.objects.filter(order_id=cart.id, id=item['id']).update(
                            quantity=item['quantity'])
                return Response({'status': True, 'edit_objects': objects_updated})
        return Response({'status': False, 'error': 'Не указаны все поля'}, status=status.HTTP_400_BAD_REQUEST)

    def delete(self, request, *args, **kwargs):
        """Функция для удаления товара из корзины"""
        items = request.data.get('items')
        if items:
            items_list = items.split(',')
            cart, _ = Order.objects.get_or_create(user_id=request.user.id, status='cart')
            query = Q()
            objects_deleted = False
            for item_id in items_list:
                if item_id.isdigit():
                    query = query | Q(order_id=cart.id, id=item_id)
                    objects_deleted = True
            if objects_deleted:
                count = OrderItem.objects.filter(query).delete()[0]
                return Response({'status': True, 'del_objects': count}, status=status.HTTP_204_NO_CONTENT)
        return Response({'status': False, 'error': 'Не указаны все поля'}, status=status.HTTP_400_BAD_REQUEST)


class OrderView(APIView):
    """Класс заказов покупателей"""
    permission_classes = [IsAuthenticated]

    def get(self, request, *args, **kwargs):
        """Функция получения списка заказанных товаров """
        order = Order.objects.filter(
            user_id=request.user.id).annotate(total_quantity=Sum('ordered_items__quantity'), total_sum=Sum(
                'ordered_items__total_amount')).distinct()
        serializer = OrderSerializer(order, many=True)
        return Response(serializer.data)

    def post(self, request, *args, **kwargs):
        """Функция подтверждения заказа"""
        if not request.user.is_authenticated:
            return Response({'Status': False, 'Error': 'Log is required'}, status=403)
        if {'id', 'contact'}.issubset(request.data):
            if request.data['id'].isdigit():
                try:
                    is_updated = Order.objects.filter(
                        user_id=request.user.id, id=request.data['id']).update(
                            contact_id=request.data['contact'], status='new')
                except IntegrityError as error:
                    print(error)
                    return Response({'Status': False, 'Errors': 'Неправильно указаны аргументы'})
                else:
                    if is_updated:
                        #on_change_order_status(request.user.id, request.data['id'])
                        return Response({'Status': True})
                    else:
                        error_message = 'Сбой'         
        return Response({'Status': False, 'Error': 'Не указаны все необходимые аргументы'})