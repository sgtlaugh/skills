from datetime import datetime, timezone


def _bucket(ts):
    return ts.replace(second=0, microsecond=0)


def current_bucket():
    return _bucket(datetime.now(timezone.utc))
