from schemas import ObjectProfile


def build_navigation_instruction(profile: ObjectProfile) -> str:
    description = profile.navigation_description.strip()
    if not description:
        raise ValueError("navigation_description must be non-empty")
    return f"Find the {description} and stop."
