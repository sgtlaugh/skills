import sqlite3


class SightingStore:
    def __init__(self, path=":memory:"):
        self.conn = sqlite3.connect(path)
        self.conn.execute(
            "CREATE TABLE IF NOT EXISTS sightings (species TEXT, count INTEGER, seen_at TEXT)"
        )

    def add(self, species, count, seen_at):
        self.conn.execute(
            "INSERT INTO sightings VALUES (?, ?, ?)", (species, count, seen_at.isoformat())
        )
        self.conn.commit()

    def list(self, limit=50):
        rows = self.conn.execute(
            "SELECT species, count, seen_at FROM sightings ORDER BY seen_at DESC LIMIT ?", (limit,)
        )
        return [{"species": s, "count": c, "seen_at": t} for s, c, t in rows]

    def by_species(self):
        rows = self.conn.execute("SELECT species, SUM(count) FROM sightings GROUP BY species")
        return dict(rows)
