def charge(order_id, amount):
    return {"order": order_id, "charged": amount}


def issue_refund(order_id, amount):
    if amount <= 0:
        raise ValueError("refund amount must be positive")
    return {"order": order_id, "refunded": amount}
