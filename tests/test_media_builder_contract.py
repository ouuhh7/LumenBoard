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


    def test_posterboard_refresh_resolves_rootless_killall_before_stock_paths(self):
        source = (ROOT / "Daemon/LBPosterBoardInstaller.m").read_text()
        self.assertIn("static NSString *LBResolveKillallExecutable(void)", source)
        rootless = source.index('@"/var/jb/usr/bin/killall"')
        rootless_bin = source.index('@"/var/jb/bin/killall"')
        stock_usr = source.index('@"/usr/bin/killall"')
        stock_bin = source.index('@"/bin/killall"')
        self.assertLess(rootless, rootless_bin)
        self.assertLess(rootless_bin, stock_usr)
        self.assertLess(stock_usr, stock_bin)
        self.assertIn("access(candidate.fileSystemRepresentation, X_OK) == 0", source)
        self.assertEqual(source.count("LBResolveKillallExecutable()"), 3)

    def test_timed_out_media_generation_is_reconciled(self):
        source = (ROOT / "Preferences/LBRootListController.m").read_text()
        self.assertIn('@"generating"', source)
        self.assertIn('@"install-media"', source)
        self.assertIn('mediaInstall ? @"installed" : @"descriptors-published"', source)


if __name__ == "__main__":
    unittest.main()
