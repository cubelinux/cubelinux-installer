#!/usr/bin/env python3
"""Limit the Fedora Anaconda GTK storage spoke to one install disk."""

from pathlib import Path
import sys


MODULE_PATHS = [
    *Path("/usr/lib64").glob("python*/site-packages/pyanaconda/ui/gui/spokes/storage.py"),
    *Path("/usr/lib").glob("python*/site-packages/pyanaconda/ui/gui/spokes/storage.py"),
]

if len(MODULE_PATHS) != 1:
    sys.exit(f"Expected one Anaconda GTK storage module, found {len(MODULE_PATHS)}")

module_path = MODULE_PATHS[0]
source = module_path.read_text()

if "# cubelinux: single install disk" in source:
    sys.exit(0)

required_fragments = (
    "class StorageSpoke",
    "def _update_disk_list(self)",
    "def on_summary_clicked(self, button)",
)
missing = [fragment for fragment in required_fragments if fragment not in source]
if missing:
    sys.exit(f"Anaconda storage module layout changed; missing: {', '.join(missing)}")

source += r'''

# cubelinux: single install disk
# Keep the most recently selected disk and clear all other disk checkboxes.
_cubelinux_update_disk_list = StorageSpoke._update_disk_list


def _cubelinux_update_single_disk_list(self, *args, **kwargs):
    previous = set(self._selected_disks)
    result = _cubelinux_update_disk_list(self, *args, **kwargs)
    overviews = self.local_overviews + self.advanced_overviews
    selected = [overview for overview in overviews if overview.get_chosen()]
    newly_selected = [
        overview for overview in selected
        if overview.device_id not in previous
    ]
    chosen = newly_selected[-1] if newly_selected else (
        selected[-1] if selected else None
    )

    for overview in overviews:
        overview.set_chosen(overview is chosen)

    self._selected_disks = [chosen.device_id] if chosen else []
    return result


StorageSpoke._update_disk_list = _cubelinux_update_single_disk_list

# The selected-disks dialog can also change the disk list. Apply the same
# single-disk rule when it closes, and synchronize the visible checkboxes.
_cubelinux_summary_clicked = StorageSpoke.on_summary_clicked


def _cubelinux_single_disk_summary_clicked(self, *args, **kwargs):
    previous = set(self._selected_disks)
    result = _cubelinux_summary_clicked(self, *args, **kwargs)
    newly_selected = [
        disk for disk in self._selected_disks
        if disk not in previous
    ]
    chosen = newly_selected[-1] if newly_selected else (
        self._selected_disks[-1] if self._selected_disks else None
    )
    self._selected_disks = [chosen] if chosen else []

    for overview in self.local_overviews + self.advanced_overviews:
        overview.set_chosen(overview.device_id == chosen)

    self._update_summary()
    return result


StorageSpoke.on_summary_clicked = _cubelinux_single_disk_summary_clicked
'''

module_path.write_text(source)
