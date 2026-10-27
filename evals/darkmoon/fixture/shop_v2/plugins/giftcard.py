def apply(order):
    return {**order, "discount": order.get("giftcard_balance", 0)}
