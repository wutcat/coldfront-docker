# coldfront-docker

Bits needed to build a production-ready ColdFront container image.

Some bits taken from the [netbox-docker][netbox-docker-github] repository.

## Image build
```
podman build -t ghcr.io/wutcat/coldfront:v1.1.5-0.0.1 -f Dockerfile .
```

## Run the image with minimal arguments for testing
```
podman run --expose 8080 --env-file env/coldfront.env -ti ghcr.io/wutcat/coldfront:v1.1.5-0.0.1
```

## Active Directory auth
When using Active Directory, for LDAP auth, it's helpful to configure some extra variables using `/etc/coldfront/local_settings.py`:
```
AUTH_LDAP_CONNECTION_OPTIONS={ldap.OPT_REFERRALS: 0}
AUTH_LDAP_BASE_DN = environ.get('AUTH_LDAP_USER_SEARCH_BASE', None)
AUTH_LDAP_USER_SEARCH = LDAPSearch(
    AUTH_LDAP_BASE_DN, ldap.SCOPE_SUBTREE, '(sAMAccountName=%(user)s)')
AUTH_LDAP_USER_ATTR_MAP = ENV.dict('AUTH_LDAP_USER_ATTR_MAP', default ={
        'username': 'sAMAccountName',
        'first_name': 'givenName',
        'last_name': 'sn',
        'email': 'mail',
    })
```
And perhaps bind mount into the container:
```
podman run --expose 8080 --env-file env/coldfront.env -v ./docker/local_settings.py:/etc/coldfront/local_settings.py -ti ghcr.io/wutcat/coldfront:v1.1.5-0.0.1
```

## ColdFront Initial Setup
This image does not try to run the `coldfront initial_setup` steps by default. To run these each time the container is launched set `CF_DO_INITIAL_SETUP=1` in `env/coldfront.env`.
