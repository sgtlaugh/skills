from datetime import datetime, timezone

from owlpost.store import SightingStore


def test_newest_first():
    store = SightingStore()
    store.add("barn owl", 2, datetime(2002, 5, 23, tzinfo=timezone.utc))
    store.add("snowy owl", 1, datetime(2025, 8, 20, tzinfo=timezone.utc))
    assert [r["species"] for r in store.list()] == ["snowy owl", "barn owl"]
