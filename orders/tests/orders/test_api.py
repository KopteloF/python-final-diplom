import pytest
from model_bakery import baker
from django.conf import settings
settings.configure()
from rest_framework.test import APIClient
#from orders.api.models import *
import json


def test_something():

 assert True