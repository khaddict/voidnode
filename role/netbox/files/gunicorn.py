bind = '127.0.0.1:8001'

workers = 5  # rule of thumb: 2n+1 where n is the number of CPU cores

threads = 3

timeout = 120

max_requests = 5000  # worker respawns after this many requests
max_requests_jitter = 500

# uncomment to accept HTTP headers with underscores (e.g. for remote auth):
# https://docs.gunicorn.org/en/stable/settings.html#header-map
# header-map = 'dangerous'
