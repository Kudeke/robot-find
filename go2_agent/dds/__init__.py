__all__ = ["LowStateSource", "SportStateSource"]


def __getattr__(name):
    if name == "LowStateSource":
        from .lowstate_source import LowStateSource

        return LowStateSource
    if name == "SportStateSource":
        from .sport_state_source import SportStateSource

        return SportStateSource
    raise AttributeError("module 'dds' has no attribute '{}'".format(name))
