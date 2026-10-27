import importlib


def apply_plugins(order, enabled):
    for name in enabled:
        order = importlib.import_module(f"shop_v2.plugins.{name}").apply(order)
    return order
