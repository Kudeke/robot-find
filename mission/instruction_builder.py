from schemas import ObjectProfile


def build_navigation_instruction(profile: ObjectProfile) -> str:
    """Build the Phase 3A instruction without another model call."""
    description = profile.navigation_description.strip()
    if not description:
        raise ValueError("navigation_description must be non-empty")
    return f"Find the {description}."
