from schemas import ObjectProfile
from mission.instruction_builder import build_navigation_instruction


profile = ObjectProfile(
    object_id="obj_test",
    name="Water Bottle",
    category="water bottle",
    visual_description="transparent bottle",
    distinctive_features=["blue cap"],
    navigation_description="transparent plastic bottle with blue cap and blue label featuring white text and wave graphic",
    created_at="2026-08-23T00:00:00Z",
)
expected = "Find the transparent plastic bottle with blue cap and blue label featuring white text and wave graphic."
assert build_navigation_instruction(profile) == expected
print("InstructionBuilder: PASS")
