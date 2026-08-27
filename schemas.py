from datetime import datetime, timezone

from pydantic import BaseModel, ConfigDict, Field, field_validator


class GeneratedObjectProfile(BaseModel):
    category: str = Field(min_length=1)
    visual_description: str = Field(min_length=1)
    distinctive_features: list[str] = Field(min_length=1)
    navigation_description: str = Field(min_length=1)

    @field_validator("distinctive_features")
    @classmethod
    def feature_strings(cls, value):
        if any(not item.strip() for item in value):
            raise ValueError("distinctive_features entries must be non-empty")
        return [item.strip() for item in value]


class ObjectProfile(GeneratedObjectProfile):
    model_config = ConfigDict(extra="forbid")
    object_id: str
    name: str = Field(min_length=1)
    created_at: str

    @classmethod
    def new(cls, object_id, name, generated):
        return cls(
            object_id=object_id,
            name=name.strip(),
            created_at=datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            **generated,
        )
