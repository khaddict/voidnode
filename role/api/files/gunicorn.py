bind = '127.0.0.1:8000'
# single worker so the in-memory per-IP rate limiter stays correct
workers = 1
worker_class = 'uvicorn.workers.UvicornWorker'
timeout = 30
# default control socket path isn't writable under ProtectHome=true
control_socket_disable = True


def on_starting(server):
    # app/main.py's rate limiter is a plain per-process dict; more than one
    # worker would silently divide its effectiveness by the worker count
    if server.cfg.workers != 1:
        raise RuntimeError(
            "workers must stay at 1: the in-memory per-IP rate limiter in "
            "app/main.py is only correct with a single worker process"
        )
