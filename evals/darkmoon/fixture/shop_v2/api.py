from shop_v2.payments import issue_refund as give_back


def refund_endpoint(request):
    return give_back(request["order_id"], request["amount"])
