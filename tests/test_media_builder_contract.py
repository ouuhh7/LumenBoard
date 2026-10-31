from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class NativeMediaPipelineContractTests(unittest.TestCase):
    def test_native_builder_emits_posterboard_descriptor_components(self):
        source = (ROOT / "Daemon/LBPosterMediaBuilder.m").read_text()
        for token in (
            "com.apple.posterkit.provider.descriptor.identifier",
            "com.apple.posterkit.role.identifier",
            "providerInfo.plist",
            "com.apple.posterkit.provider.contents.userInfo",
            "Wallpaper.plist",
            "PF_Background.ca",
            "PF_Floating.ca",
            "main.caml",
            "index.xml",
            "AVAssetImageGenerator",
            "CAKeyframeAnimation",
        ):
            with self.subTest(token=token):
                self.assertIn(token, source)

    def test_daemon_has_hash_checked_media_install_action(self):
        source = (ROOT / "Daemon/main.m").read_text()
        self.assertIn('isEqualToString:@"install-media"', source)
        self.assertIn("LBPosterMediaBuilder buildDescriptorForSource", source)
        self.assertIn("LBSHA256(sourcePath)", source)
        self.assertIn("installExtractedDescriptorTreeAtPath:generatedRoot", source)

    def test_preferences_queue_media_instead_of_storing_only(self):
        source = (ROOT / "Preferences/LBRootListController.m").read_text()
        self.assertIn('LBQueueDaemonActionAndWait(identifier, @"install-media"', source)
        self.assertIn('manifest[@"installationState"] = @"installed"', source)
        self.assertIn('title = @"Wallpaper descriptor registered"', source)

    def test_refresh_is_requested_after_media_publication(self):
        source = (ROOT / "Daemon/main.m").read_text()
        self.assertIn("requestPosterBoardRefreshForContainer:container", source)


if __name__ == "__main__":
    unittest.main()
