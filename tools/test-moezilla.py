#!/usr/bin/env python3
"""Moezilla source and integration-contract tests (not a substitute for device tests)."""
import plistlib
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


class MoezillaConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.info = plistlib.loads((ROOT / "browser/Reynard/Resources/Info.plist").read_bytes())

    def source(self, rel):
        return (ROOT / rel).read_text()

    def test_independent_browser_identity(self):
        config = self.source("browser/Configuration/Reynard.xcconfig")
        self.assertIn("APP_DISPLAY_NAME = Moezilla", config)
        project = self.source("browser/Reynard.xcodeproj/project.pbxproj")
        self.assertIn("com.bonewizardry.Moezilla", project)
        self.assertNotIn('PRODUCT_BUNDLE_IDENTIFIER = "com.minh-ton.Reynard"', project)

    def test_custom_scheme_matches_scene_delegate(self):
        schemes = self.info["CFBundleURLTypes"][0]["CFBundleURLSchemes"]
        self.assertIn("moezilla", schemes)
        self.assertNotIn("reynard", schemes)
        self.assertIn('scheme == "moezilla"', self.source("browser/Reynard/SceneDelegate.swift"))

    def test_background_task_registration_contract(self):
        code = self.source("browser/Reynard/BackgroundDebuggingSession.swift")
        ids = self.info["BGTaskSchedulerPermittedIdentifiers"]
        self.assertEqual(ids, ["com.bonewizardry.Moezilla.backgroundDebugging"])
        self.assertIn(ids[0], code)
        self.assertIn("processing", self.info["UIBackgroundModes"])
        self.assertIn("BGContinuedProcessingTaskRequest", code)

    def test_explicit_start_and_stop_controls(self):
        ui = self.source(
            "browser/Reynard/Client/Interface/Library/Settings/Sections/Advanced/Developer/"
            "DeveloperPreferencesViewController.swift"
        )
        self.assertIn("Continue debugging in background", ui)
        self.assertIn("BackgroundDebuggingSession.shared.start()", ui)
        self.assertIn("BackgroundDebuggingSession.shared.stop()", ui)

    def test_gecko_foreground_lifecycle(self):
        scene = self.source("browser/Reynard/SceneDelegate.swift")
        self.assertIn("guard !BackgroundDebuggingSession.shared.isRunning", scene)
        self.assertIn("restoreRemoteDebuggingOnForeground()", scene)

    def test_address_bar_docks_on_direct_focus(self):
        src = self.source("browser/Reynard/Client/Interface/BrowserViewController.swift")
        self.assertIn("searchOverlayCoordinator.isFocused || browserChrome.isAddressBarEditing", src)
        self.assertIn("browserChrome.dockAddressBar(offset: shouldDockAddressBar", src)

    def test_webpage_typing_uses_native_replacement_on_ios27(self):
        patch = self.source("patches/widget/uikit/GeckoEditableSupport.mm.patch")
        insert = patch.split("+- (void)insertText:(NSString*)aText {", 1)[1].split(
            "+- (void)replaceRange:(UITextRange*)aRange", 1
        )[0]
        self.assertIn("@available(iOS 27.0, *)", insert)
        self.assertIn("handler->ReplaceRange(range, aText)", insert)
        self.assertIn("handler->InsertText(aText)", insert)
        self.assertIn("self.markedTextRange == nil", insert)

    def test_gecko_patch_applies_as_valid_new_file(self):
        patch = ROOT / "patches/widget/uikit/GeckoEditableSupport.mm.patch"
        with tempfile.TemporaryDirectory() as temp:
            check = subprocess.run(
                ["git", "apply", "--check", str(patch)], cwd=temp,
                capture_output=True, text=True,
            )
        self.assertEqual(check.returncode, 0, check.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
