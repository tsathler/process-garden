"""Process Garden's standalone process collector."""

__all__ = ["ProcessCollector", "ProcessRecord", "Snapshot"]


def __getattr__(name: str):
    """Load collector types lazily, keeping ``python -m`` entry points clean."""
    if name in __all__:
        from .collector import ProcessCollector, ProcessRecord, Snapshot

        return {
            "ProcessCollector": ProcessCollector,
            "ProcessRecord": ProcessRecord,
            "Snapshot": Snapshot,
        }[name]
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
