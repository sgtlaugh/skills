class WebhookRouter:
    def dispatch(self, event, payload):
        handler = getattr(self, f"handle_{event}", None)
        if handler is None:
            return {"ignored": event}
        return handler(payload)

    def handle_payment(self, payload):
        return {"paid": payload["order_id"]}

    def handle_chargeback(self, payload):
        return {"disputed": payload["order_id"]}


def export_legacy_csv(rows):
    return "\n".join(",".join(map(str, r)) for r in rows)
