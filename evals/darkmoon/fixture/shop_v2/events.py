HANDLERS = {}


def on(event):
    def register(fn):
        HANDLERS[event] = fn
        return fn
    return register


@on("dispute")
def handle_dispute(payload):
    return {"dispute_opened": payload["order_id"]}


def route(event, payload):
    return HANDLERS[event](payload)
