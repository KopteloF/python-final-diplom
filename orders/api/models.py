from django.db import models

# Create your models here.
from django.contrib.auth.base_user import BaseUserManager
from django.contrib.auth.models import AbstractUser
from django.utils.translation import gettext_lazy as _
from django_rest_passwordreset.tokens import get_token_generator


USER_TYPE_CHOICES = (
    ('shop', 'Магазин'),
    ('buyer', 'Покупатель'),
)

STATE_CHOICES = (
    ('cart', 'В корзине'),
    ('new', 'Новый'),
    ('confirmed', 'Подтвержден'),
    ('assembled', 'Собран'),
    ('sent', 'Отправлен'),
    ('delivered', 'Доставлен'),
    ('canceled', 'Отменен'),
)


class UserManager(BaseUserManager):
    """
    Миксин для управления пользователями
    """
    use_in_migrations = True

    def _create_user(self, email, password, **extra_fields):
        """
        Create and save a user with the given username, email, and password.
        """
        if not email:
            raise ValueError('Email address must be set')
        if not password:
            raise ValueError('Password must be provided')

        email = self.normalize_email(email)
        user = self.model(email=email, **extra_fields)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_user(self, email=None, password=None, **extra_fields):
        extra_fields.setdefault('is_staff', False)
        extra_fields.setdefault('is_superuser', False)
        return self._create_user(email, password, **extra_fields)

    def create_superuser(self, email, password, **extra_fields):
        extra_fields.setdefault('is_staff', True)
        extra_fields.setdefault('is_superuser', True)
        extra_fields.setdefault('is_active', True)

        return self._create_user(email, password, **extra_fields)


class User(AbstractUser):
    """
    Стандартная модель пользователей
    """
    USERNAME_FIELD = 'email'
    REQUIRED_FIELDS = []

    objects = UserManager()

    username = None
    email = models.EmailField(_('email address'), unique=True)
    company = models.CharField(verbose_name='Компания', max_length=40, blank=True)
    position = models.CharField(verbose_name='Должность', max_length=40, blank=True)
    is_active = models.BooleanField(
         ('active'), default=False, help_text=_(
            'Designates whether this user should be treated as active. '
            'Unselect this instead of deleting accounts.'),)
    type = models.CharField(verbose_name='Тип пользователя', choices=USER_TYPE_CHOICES, max_length=5, default='buyer')

    def __str__(self):
        return f'{self.first_name} {self.last_name}'

    class Meta:
        verbose_name = 'Пользователь'
        verbose_name_plural = "Список пользователей"
        ordering = ('email',)


class Contact(models.Model):
    user = models.ForeignKey(User, verbose_name='Пользователь', related_name='contacts', blank=True, on_delete=models.CASCADE)
    city = models.CharField(max_length=50, verbose_name='Город')
    street = models.CharField(max_length=100, verbose_name='Улица')
    house = models.CharField(max_length=15, verbose_name='Дом', blank=True)
    structure = models.CharField(max_length=15, verbose_name='Корпус', blank=True)
    building = models.CharField(max_length=15, verbose_name='Строение', blank=True)
    apartment = models.CharField(max_length=15, verbose_name='Квартира', blank=True)
    phone = models.CharField(max_length=20, verbose_name='Телефон')

    class Meta:
        verbose_name = 'Контакты пользователя'
        verbose_name_plural = "Список контактов пользователя"

    def __str__(self):
        return f'{self.city}, ул.{self.street}, дом {self.house} ({self.phone})'


class ConfirmEmailToken(models.Model):
    user = models.ForeignKey(User, related_name='confirm_email_tokens', on_delete=models.CASCADE,
		verbose_name="The User which is associated to this password reset token")
    created_at = models.DateTimeField(auto_now_add=True, verbose_name="When was this token generated")
    key = models.CharField(_("Key"), max_length=64, db_index=True, unique=True)

    class Meta:
        verbose_name = 'Токен подтверждения Email'
        verbose_name_plural = 'Токены подтверждения Email'

    @staticmethod
    def generate_key():
        return get_token_generator().generate_token()

    def save(self, *args, **kwargs):
        if not self.key:
            self.key = self.generate_key()
        return super(ConfirmEmailToken, self).save(*args, **kwargs)

    def __str__(self):
        return f"Токен подтверждения Email для пользователя {self.user}"


class Shop(models.Model):
	name = models.CharField(max_length=50, verbose_name='Название')
	url = models.URLField(verbose_name='Ссылка на файл прайса', null=True, blank=True)
	user = models.OneToOneField(User, verbose_name='Пользователь', blank=True, null=True, on_delete=models.CASCADE)
	state = models.BooleanField(verbose_name='Cтатус получения заказов', default=True)

	class Meta:
		verbose_name = 'Магазин'
		verbose_name_plural = "Список магазинов"
		ordering = ('-name',)

	def __str__(self):
		return self.name
     
class Category(models.Model):
	name = models.CharField(max_length=40, verbose_name='Название')
	shops = models.ManyToManyField(Shop, verbose_name='Магазины', related_name='categories', blank=True)

	class Meta:
		verbose_name = 'Категория'
		verbose_name_plural = "Список категорий"
		ordering = ('-name',)

	def __str__(self):
		return self.name
      

class Parameter(models.Model):
	name = models.CharField(max_length=40, verbose_name='Название')

	class Meta:
		verbose_name = 'Имя параметра'
		verbose_name_plural = "Список имен параметров"
		ordering = ('-name',)

	def __str__(self):
		return self.name
      

class Order(models.Model):
	user = models.ForeignKey(User, verbose_name='Пользователь', related_name='shopAPI', blank=True,
		on_delete=models.CASCADE)
	status = models.CharField(verbose_name='Статус', choices=STATE_CHOICES, max_length=15, default='cart')
	contact = models.ForeignKey(Contact, verbose_name='Контакт', blank=True, null=True,
		on_delete=models.CASCADE)
	created = models.DateTimeField(auto_now_add=True)
	updated = models.DateTimeField(auto_now=True)

	class Meta:
		verbose_name = 'Заказ'
		verbose_name_plural = "Список заказов"
		ordering = ('-created',)

	def __str__(self):
		return str(self.created)
		# return self.created


class OrderItem(models.Model):
	order = models.ForeignKey(Order, verbose_name='Заказ', related_name='ordered_items', blank=True,
		on_delete=models.CASCADE)
	external_id = models.PositiveIntegerField(verbose_name='Внешний ИД')
	quantity = models.PositiveIntegerField(default=1, verbose_name='Количество')
	price = models.PositiveIntegerField(default=0, verbose_name='Цена')
	total_amount = models.PositiveIntegerField(default=0, verbose_name='Общая стоимость')

	class Meta:
		verbose_name = 'Заказанная позиция'
		verbose_name_plural = "Список заказанных позиций"
		constraints = [
			models.UniqueConstraint(fields=['order_id', 'product_name'], name='unique_order_item'), ]

	def __str__(self):
		return self.product_name

	def save(self, *args, **kwargs):
		self.total_amount = self.price * self.quantity
		super(OrderItem, self).save(*args, **kwargs)