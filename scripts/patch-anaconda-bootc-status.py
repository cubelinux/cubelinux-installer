#!/usr/bin/env python3
"""Keep Anaconda's bootc deployment status visibly active."""

from pathlib import Path
import sys


MODULE_PATHS = [
    *Path("/usr/lib64").glob(
        "python*/site-packages/pyanaconda/modules/payloads/payload/rpm_ostree/installation.py"
    ),
    *Path("/usr/lib").glob(
        "python*/site-packages/pyanaconda/modules/payloads/payload/rpm_ostree/installation.py"
    ),
]

if len(MODULE_PATHS) != 1:
    sys.exit(f"Expected one Anaconda bootc installation module, found {len(MODULE_PATHS)}")

module_path = MODULE_PATHS[0]
source = module_path.read_text()

if "# cubelinux: bootc activity status" in source:
    sys.exit(0)

required_fragments = (
    "class DeployBootcTask(Task)",
    "def run(self):",
    "for line in execReadlines(bootc_cmd, bootc_args):",
)
missing = [fragment for fragment in required_fragments if fragment not in source]
if missing:
    sys.exit(
        "Anaconda bootc installation module layout changed; missing: "
        + ", ".join(missing)
    )

source += r'''

# cubelinux: bootc activity status
# bootc install to-filesystem doesn't currently expose machine-readable
# progress events. Refresh the task message during long quiet periods so the
# installer makes it clear that image deployment is still running. Keep the
# task's numeric progress unchanged until Anaconda receives a real milestone.
from threading import Event as _Event
from threading import Thread as _Thread
from time import monotonic as _monotonic


_cubelinux_original_deploy_bootc_run = DeployBootcTask.run


def _cubelinux_deploy_bootc_with_activity_status(self, *args, **kwargs):
    stop_status = _Event()
    started_at = _monotonic()

    def _report_activity():
        while not stop_status.wait(5):
            elapsed = int(_monotonic() - started_at)
            minutes, seconds = divmod(elapsed, 60)
            if minutes:
                elapsed_text = _("{}m {}s").format(minutes, seconds)
            else:
                elapsed_text = _("{}s").format(seconds)
            self.report_progress(
                _("Deploying bootc image; elapsed time: {}").format(elapsed_text)
            )

    status_thread = None
    try:
        status_thread = _Thread(
            target=_report_activity,
            name="cubelinux-bootc-activity-status",
            daemon=True,
        )
        status_thread.start()
    except RuntimeError as error:
        status_thread = None
        log.warning("Bootc status refresh unavailable; continuing installation: %s", error)

    try:
        return _cubelinux_original_deploy_bootc_run(self, *args, **kwargs)
    finally:
        stop_status.set()
        if status_thread is not None:
            status_thread.join()


DeployBootcTask.run = _cubelinux_deploy_bootc_with_activity_status
'''

try:
    compile(source, str(module_path), "exec")
except SyntaxError as error:
    sys.exit(f"Generated Anaconda bootc status patch is invalid: {error}")

module_path.write_text(source)
