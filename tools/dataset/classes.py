"""HaGRID label → EasyControl pose class mapping (see docs/superpowers/plans/2026-10-30-easycontrol-m3.md)."""

# Same order and raw values as Swift `PoseClass` (minus pinch, which HaGRID doesn't have).
TARGET_CLASSES = ["openPalm", "fist", "point", "two", "three", "ok", "thumbsUp", "thumbsDown", "none"]

_POSITIVE = {
    "palm": "openPalm",
    "stop": "openPalm",
    "fist": "fist",
    "one": "point",
    "peace": "two",
    "two_up": "two",
    "three": "three",
    "three2": "three",
    "three3": "three",
    "ok": "ok",
    "like": "thumbsUp",
    "dislike": "thumbsDown",
}

# Look-alikes first: they teach the model what is *not* one of our poses.
NONE_SOURCES = [
    "no_gesture", "four", "point", "thumb_index", "thumb_index2", "grip", "grabbing", "call", "rock", "mute",
    "little_finger", "middle_finger", "hand_heart", "hand_heart2", "holy", "take_picture", "timeout", "xsign",
    "peace_inverted", "two_up_inverted", "stop_inverted",
]

POSITIVE_SOURCES = list(_POSITIVE)
SOURCE_TO_TARGET = {**_POSITIVE, **{s: "none" for s in NONE_SOURCES}}

SPLIT_SIZES = {
    "positive": {"train": 900, "val": 150, "test": 250},
    "none": {"train": 200, "val": 40, "test": 60},
}
