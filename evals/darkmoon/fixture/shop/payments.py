def charge(order_id, amount):
    """Legacy charge path, kept for old invoices."""
    return {"order": order_id, "charged": amount}
