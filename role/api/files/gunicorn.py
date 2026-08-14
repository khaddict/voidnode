bind = '127.0.0.1:8000'
# single worker so the in-memory per-IP rate limiter stays correct
workers = 1
worker_class = 'uvicorn.workers.UvicornWorker'
timeout = 30
# default control socket path isn't writable under ProtectHome=true
control_socket_disable = True
