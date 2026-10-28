import csv
import io

from owlpost.store import SightingStore
from owlpost.time_utils import current_bucket

store = SightingStore()


def record(args):
    store.add(args["species"], int(args.get("count", 1)), current_bucket())
    return {"ok": True}


def list_sightings(args):
    return {"sightings": store.list()}


def species_summary(args):
    totals = store.by_species()
    return {"species": sorted(totals.items(), key=lambda kv: -kv[1])}


def export(args):
    out = io.StringIO()
    writer = csv.writer(out)
    for row in store.list():
        writer.writerow([row["species"], row["count"], row["seen_at"]])
    return out.getvalue()
