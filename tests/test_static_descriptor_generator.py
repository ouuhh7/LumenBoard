import plistlib
import sys
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import static_descriptor_generator as generator
from descriptor_consistency import validate_descriptors_root

# Small locally generated JPEG fixture; no third-party wallpaper assets.
JPEG_PATH = Path(__file__).resolve().parent / "fixtures" / "synthetic.jpg"


class StaticDescriptorGeneratorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name)
        self.image = self.base / "input.jpg"
        self.image.write_bytes(JPEG_PATH.read_bytes())
        self.output = self.base / "descriptors"
        self.output.mkdir()

    def tearDown(self):
        self.temp.cleanup()

    def test_generates_complete_tree_and_passes_internal_validator(self):
        result = generator.generate_static_descriptor(self.image, self.output, "Test Poster")
        descriptor = self.output / result["descriptor_uuid"]
        contents = descriptor / "versions/1/contents"
        wallpaper_name = f"{result['descriptor_uuid']}.Custom.wallpaper"
        wallpaper = contents / wallpaper_name
        self.assertEqual(result["status"], "generated-structurally-validated-candidate-not-device-verified")
        self.assertTrue((descriptor / "com.apple.posterkit.provider.descriptor.identifier").is_file())
        self.assertTrue((descriptor / "com.apple.posterkit.role.identifier").is_file())
        self.assertTrue((descriptor / "providerInfo.plist").is_file())
        self.assertTrue((contents / "com.apple.posterkit.provider.contents.userInfo").is_file())
        self.assertTrue((wallpaper / "Wallpaper.plist").is_file())
        self.assertTrue((wallpaper / "PF_Background.ca/assets/0.jpg").is_file())
        self.assertTrue((wallpaper / "PF_Background.ca/main.caml").is_file())
        self.assertTrue((wallpaper / "PF_Floating.ca/main.caml").is_file())
        background_index = (wallpaper / "PF_Background.ca/index.xml").read_bytes()
        self.assertTrue(background_index.startswith(b"bplist00"))
        index = plistlib.loads(background_index)
        self.assertEqual(set(index), {
            "assetManifest", "documentHeight", "documentResizesToView",
            "documentWidth", "geometryFlipped", "rootDocument",
            "scalesToFitInPlayer", "unitsInPixelsInPlayer",
        })
        self.assertIs(index["unitsInPixelsInPlayer"], True)
        floating_index = plistlib.loads((wallpaper / "PF_Floating.ca/index.xml").read_bytes())
        self.assertEqual(floating_index["documentWidth"], 1)
        self.assertEqual(floating_index["documentHeight"], 1)
        self.assertIs(floating_index["unitsInPixelsInPlayer"], True)
        report = validate_descriptors_root(self.output)
        self.assertEqual(report["status"], "passes-structural-checks", report)
        self.assertEqual(report["errors"], [])
        self.assertEqual(report["warnings"], [])
        self.assertEqual(result["compatibility"]["native_gallery_on_iphone_x_ios_16_7_16"], "not-tested")

    def test_objc_media_builder_matches_ios16_posterforge_index_contract(self):
        source = (Path(__file__).resolve().parents[1] / "Daemon" / "LBPosterMediaBuilder.m").read_text(encoding="utf-8")
        self.assertIn('return LBMediaWritePlist(index, [directory stringByAppendingPathComponent:@"index.xml"], error);', source)
        self.assertNotIn("LBMediaWriteXMLPlist", source)
        self.assertIn('@"geometryFlipped":@NO', source)
        self.assertIn('@"rootDocument":@"main.caml"', source)
        self.assertIn('@"unitsInPixelsInPlayer":@YES', source)
        self.assertIn(r'bounds=\"0 0 1 1\"', source)
        self.assertIn(r'position=\"0.5 0.5\"', source)
        self.assertIn(r'version=\"1.0\"', source)
        self.assertNotIn(r'version=\\"1.0\\"', source)
        self.assertIn("writeEmptyLayerAt:floating error:error", source)

    def test_wallpaper_ids_are_unique_across_generated_descriptors(self):
        one = generator.generate_static_descriptor(self.image, self.output, "One")
        two = generator.generate_static_descriptor(self.image, self.output, "Two")
        self.assertNotEqual(one["descriptor_uuid"], two["descriptor_uuid"])
        self.assertNotEqual(one["wallpaper_identifier"], two["wallpaper_identifier"])
        report = validate_descriptors_root(self.output)
        self.assertEqual(report["status"], "passes-structural-checks", report)
        self.assertEqual(len(report["descriptors"]), 2)

    def test_repeated_provider_and_wallpaper_ids_are_consistent(self):
        result = generator.generate_static_descriptor(self.image, self.output, "Meta")
        descriptor = self.output / result["descriptor_uuid"]
        contents = descriptor / "versions/1/contents"
        wallpaper = next(contents.glob("*.wallpaper"))
        wp = plistlib.loads((wallpaper / "Wallpaper.plist").read_bytes())
        user = plistlib.loads((contents / "com.apple.posterkit.provider.contents.userInfo").read_bytes())
        root_id = (descriptor / "com.apple.posterkit.provider.descriptor.identifier").read_text()
        self.assertEqual(wp["identifier"], result["wallpaper_identifier"])
        self.assertEqual(wp["assets"]["lockAndHome"]["default"]["identifier"], wp["identifier"])
        self.assertEqual(user["wallpaperRepresentingIdentifier"], str(wp["identifier"]))
        self.assertEqual(root_id, user["wallpaperRepresentingIdentifier"])
        self.assertEqual(user["wallpaperRepresentingFileName"], wallpaper.name)

    def test_rejects_png_instead_of_mislabeling_it_as_jpeg(self):
        png = self.base / "input.png"
        png.write_bytes(b"\x89PNG\r\n\x1a\n" + b"synthetic")
        with self.assertRaisesRegex(generator.GeneratorError, "must be JPEG"):
            generator.generate_static_descriptor(png, self.output, "PNG")
        self.assertEqual(list(self.output.iterdir()), [])

    def test_rejects_corrupt_jpeg_before_creating_output(self):
        bad = self.base / "bad.jpg"
        bad.write_bytes(b"\xff\xd8\xffnot-a-jpeg\xff\xd9")
        with self.assertRaises(generator.GeneratorError):
            generator.generate_static_descriptor(bad, self.output, "Bad")
        self.assertEqual(list(self.output.iterdir()), [])

    def test_rejects_invalid_title(self):
        with self.assertRaisesRegex(generator.GeneratorError, "title must contain"):
            generator.generate_static_descriptor(self.image, self.output, "!!!")
        self.assertEqual(list(self.output.iterdir()), [])

    def test_rejects_symlink_source(self):
        link = self.base / "linked.jpg"
        link.symlink_to(self.image)
        with self.assertRaisesRegex(generator.GeneratorError, "non-symlink"):
            generator.generate_static_descriptor(link, self.output, "Link")
        self.assertEqual(list(self.output.iterdir()), [])

    def test_existing_output_descriptor_is_not_modified(self):
        one = generator.generate_static_descriptor(self.image, self.output, "First")
        before = (self.output / one["descriptor_uuid"] / "com.apple.posterkit.role.identifier").read_bytes()
        # The generator allocates a fresh ID and never reuses/overwrites the first directory.
        generator.generate_static_descriptor(self.image, self.output, "Second")
        after = (self.output / one["descriptor_uuid"] / "com.apple.posterkit.role.identifier").read_bytes()
        self.assertEqual(before, after)

    def test_provider_info_is_keyed_archive_plist(self):
        result = generator.generate_static_descriptor(self.image, self.output, "Archive")
        data = plistlib.loads((self.output / result["descriptor_uuid"] / "providerInfo.plist").read_bytes())
        self.assertEqual(data["$archiver"], "NSKeyedArchiver")
        self.assertEqual(data["$top"]["root"], plistlib.UID(1))

    def test_generator_failure_rolls_back_staging_directory(self):
        with patch.object(generator, "_validate_staged", side_effect=generator.GeneratorError("forced validation failure")):
            with self.assertRaisesRegex(generator.GeneratorError, "forced validation failure"):
                generator.generate_static_descriptor(self.image, self.output, "Rollback")
        self.assertEqual(list(self.output.iterdir()), [])
        self.assertFalse(any(p.name.startswith(".lumenboard-stage-") for p in self.output.iterdir()))
        self.assertFalse(any(p.name.startswith(".lumenboard-validation-") for p in self.output.iterdir()))


if __name__ == "__main__":
    unittest.main()
