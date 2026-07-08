import pytest
from api.models import User


@pytest.mark.django_db
def test_products_list_returns_200(api_client):
    response = api_client.get('/products')
    assert response.status_code == 200
    assert isinstance(response.json(), list)


@pytest.mark.django_db
def test_shops_list_returns_200(api_client):
    response = api_client.get('/shops')
    assert response.status_code == 200


@pytest.mark.django_db
def test_partner_update_requires_auth(api_client):
    response = api_client.post('/partner/update', {'url': 'http://example.com/price.yaml'})
    assert response.status_code == 401


@pytest.mark.django_db
def test_register_user_creates_user(api_client):
    payload = {
        'first_name': 'Test',
        'last_name': 'User',
        'email': 'newuser@example.com',
        'password': 'Str0ngPass!123',
        'company': 'ACME',
        'position': 'manager',
    }
    response = api_client.post('/user/register', payload)
    assert response.status_code == 200
    assert response.json()['status'] is True
    assert User.objects.filter(email='newuser@example.com').exists()


@pytest.mark.django_db
def test_register_user_missing_fields_returns_400(api_client):
    response = api_client.post('/user/register', {'email': 'x@example.com'})
    assert response.status_code == 400
