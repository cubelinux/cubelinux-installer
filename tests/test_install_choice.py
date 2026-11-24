import importlib.util
from pathlib import Path
import sys
import types
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / "config/calamares/custom-modules/cubelinux-erase-only/main.py"


class InstallationChoiceTests(unittest.TestCase):
    def run_job(self, choices):
        calamares = types.SimpleNamespace(
            globalstorage=types.SimpleNamespace(value=lambda key: choices if key == "partitionChoices" else None)
        )
        spec = importlib.util.spec_from_file_location("erase_only", MODULE)
        module = importlib.util.module_from_spec(spec)
        with patch.dict(sys.modules, {"libcalamares": calamares}):
            spec.loader.exec_module(module)
            return module.run()

    def test_erase_is_accepted(self):
        self.assertIsNone(self.run_job({"install": "erase", "swap": "none"}))

    def test_unsupported_and_missing_choices_are_rejected(self):
        for choice in ({"install": "alongside"}, {"install": "replace"}, {}, None):
            with self.subTest(choice=choice):
                error = self.run_job(choice)
                self.assertIn("No disk changes were made", error[1])

    def test_check_runs_before_partition_jobs(self):
        settings = (ROOT / "config/calamares/settings.conf").read_text()
        exec_phase = settings.split("  - exec:", 1)[1]
        self.assertLess(exec_phase.index("- cubelinux-erase-only"), exec_phase.index("- partition"))


if __name__ == "__main__":
    unittest.main()
