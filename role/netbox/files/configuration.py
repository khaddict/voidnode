# write access is denied for hostnames not in this list; the first entry is the preferred name
ALLOWED_HOSTS = ['{{ fqdn }}', '{{ ip }}']

# see Django docs for the full parameter list: https://docs.djangoproject.com/en/stable/ref/settings/#databases
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': 'netbox',
        'USER': 'netbox',
        'PASSWORD': '{{ psql_password }}',
        'HOST': 'localhost',
        'PORT': '',  # blank uses the default port
        'CONN_MAX_AGE': 300,
    }
}

# separate caching/task Redis configs; recommended to use different database IDs for each
REDIS = {
    'tasks': {
        'HOST': 'localhost',
        'PORT': 6379,
        # uncomment to use Redis Sentinel instead of HOST/PORT
        # 'SENTINELS': [('mysentinel.redis.example.com', 6379)],
        # 'SENTINEL_SERVICE': 'netbox',
        'USERNAME': '',
        'PASSWORD': '',
        'DATABASE': 0,
        'SSL': False,
        # skips TLS cert verification; can expose the connection to attacks
        # 'INSECURE_SKIP_TLS_VERIFY': False,
        # path to a CA cert, typically used with a self-signed certificate
        # 'CA_CERT_PATH': '/etc/ssl/certs/ca.crt',
    },
    'caching': {
        'HOST': 'localhost',
        'PORT': 6379,
        # see tasks: Sentinel option
        # 'SENTINELS': [('mysentinel.redis.example.com', 6379)],
        # 'SENTINEL_SERVICE': 'netbox',
        'USERNAME': '',
        'PASSWORD': '',
        'DATABASE': 1,
        'SSL': False,
        # see tasks: skip TLS verify
        # 'INSECURE_SKIP_TLS_VERIFY': False,
        # see tasks: CA cert path
        # 'CA_CERT_PATH': '/etc/ssl/certs/ca.crt',
    }
}

# never expose outside this file; must be defined, ideally 50+ chars mixing letters/numbers/symbols
SECRET_KEY = '{{ secret_key }}'

# enables v2 API tokens (NetBox v4.5+); each pepper must be at least 50 characters
API_TOKEN_PEPPERS = {
    1: '{{ api_token_peppers }}',
}


# admins get notified of application errors, if email settings are configured
ADMINS = [
    # ('John Doe', 'jdoe@example.com'),
]

# see Django docs for available validators: https://docs.djangoproject.com/en/stable/topics/auth/passwords/#password-validation
AUTH_PASSWORD_VALIDATORS = [
    # {
    #     'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator',
    #     'OPTIONS': {
    #         'min_length': 10,
    #     }
    # },
]

# set this if NetBox is served from a subdirectory, e.g. BASE_PATH = 'netbox/'
BASE_PATH = ''

# if CORS_ORIGIN_ALLOW_ALL is False, allow origins via CORS_ORIGIN_WHITELIST or _REGEX_WHITELIST instead
CORS_ORIGIN_ALLOW_ALL = False
CORS_ORIGIN_WHITELIST = [
    # 'https://hostname.example.com',
]
CORS_ORIGIN_REGEX_WHITELIST = [
    # r'^(https?://)?(\w+\.)?example\.com$',
]

CSRF_COOKIE_NAME = 'csrftoken'

# WARNING: substantial performance penalty and may leak sensitive info; never enable in production
DEBUG = False

DEFAULT_LANGUAGE = 'en-us'

EMAIL = {
    'SERVER': 'localhost',
    'PORT': 25,
    'USERNAME': '',
    'PASSWORD': '',
    'USE_SSL': False,
    'USE_TLS': False,
    'TIMEOUT': 10,  # seconds
    'FROM_EMAIL': '',
}

# models listed here (or '*' for all) become viewable by all users, including anonymous ones
EXEMPT_VIEW_PERMISSIONS = [
    # 'dcim.site',
    # 'dcim.region',
    # 'ipam.prefix',
]

# HTTP proxies NetBox should use when sending outbound HTTP requests (e.g. for webhooks).
# HTTP_PROXIES = {
#     'http': 'http://10.10.1.10:3128',
#     'https': 'http://10.10.1.10:1080',
# }

# the debugging toolbar is only available to clients accessing NetBox from one of these IPs
INTERNAL_IPS = ('127.0.0.1', '::1')

# see Django docs for logging config: https://docs.djangoproject.com/en/stable/topics/logging/
LOGGING = {}

# resets session lifetime on each request, keeping authenticated users logged in indefinitely
LOGIN_PERSISTENCE = False

# if False, unauthenticated users can view most of NetBox but not make changes
LOGIN_REQUIRED = True

# seconds before a logged-in web session must re-authenticate (default: 1209600, 14 days)
LOGIN_TIMEOUT = None

# hides the login form; useful when only allowing SSO
LOGIN_FORM_HIDDEN = False

LOGOUT_REDIRECT_URL = 'home'

# defaults to a path derived from the install location
# MEDIA_ROOT = '/opt/netbox/netbox/media'

# exposes Prometheus metrics at /metrics
METRICS_ENABLED = False

PLUGINS = []

# each key is a plugin name; its value is that plugin's settings dict
# PLUGINS_CONFIG = {
#     'my_plugin': {
#         'foo': 'bar',
#         'buzz': 'bazz'
#     }
# }

REMOTE_AUTH_ENABLED = False
REMOTE_AUTH_BACKEND = 'netbox.authentication.RemoteUserBackend'
REMOTE_AUTH_HEADER = 'HTTP_REMOTE_USER'
REMOTE_AUTH_USER_FIRST_NAME = 'HTTP_REMOTE_USER_FIRST_NAME'
REMOTE_AUTH_USER_LAST_NAME = 'HTTP_REMOTE_USER_LAST_NAME'
REMOTE_AUTH_USER_EMAIL = 'HTTP_REMOTE_USER_EMAIL'
REMOTE_AUTH_AUTO_CREATE_USER = True
REMOTE_AUTH_DEFAULT_GROUPS = []
REMOTE_AUTH_DEFAULT_PERMISSIONS = {}

# checks for a new NetBox release; set to None to disable
RELEASE_CHECK_URL = None
# RELEASE_CHECK_URL = 'https://api.github.com/repos/netbox-community/netbox/releases'

# see MEDIA_ROOT: derived default path
# REPORTS_ROOT = '/opt/netbox/netbox/reports'

RQ_DEFAULT_TIMEOUT = 300  # seconds

# see MEDIA_ROOT: derived default path
# SCRIPTS_ROOT = '/opt/netbox/netbox/scripts'

SESSION_COOKIE_NAME = 'sessionid'

# alternative to DB-stored sessions; useful for auth on a standby instance with read-only DB access
SESSION_FILE_PATH = None

# base 10 (1000) is default; set to 1024 for base 2 units
# DISK_BASE_UNIT = 1024
# RAM_BASE_UNIT = 1024

# "default" is for image uploads, "staticfiles" for static files, "scripts" for custom scripts
# STORAGES = {
#     "default": {
#         "BACKEND": "django.core.files.storage.FileSystemStorage",
#     },
#     "staticfiles": {
#         "BACKEND": "django.contrib.staticfiles.storage.StaticFilesStorage",
#     },
#     "scripts": {
#         "BACKEND": "extras.storage.ScriptFileSystemStorage",
#         "OPTIONS": {
#             "allow_overwrite": True,
#         },
#     },
# }

TIME_ZONE = 'UTC'
