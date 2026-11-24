"""Reject unsupported partition choices before any disk jobs run."""

import libcalamares


def pretty_name():
    return "Checking the installation method"


def run():
    choices = libcalamares.globalstorage.value("partitionChoices")
    if isinstance(choices, dict) and choices.get("install") == "erase":
        return None
    return (
        "Unsupported installation method",
        "Choose Erase disk to install cubelinux with its factory reset partition. "
        "No disk changes were made.",
    )
