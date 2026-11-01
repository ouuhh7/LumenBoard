import io
import subprocess
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VERIFIER = ROOT / "tools" / "verify_deb_ownership.py"


def _ar_member(name: str, content: bytes) -> bytes:
    header = (
        f"{name + '/':<16}"
        f"{0:<12}"
        f"{0:<6}"
        f"{0:<6}"
        f"{0o100644:<8o}"
        f"{len(content):<10}"
        "`\n"
    ).encode("ascii")
    return header + content + (b"\n" if len(content) % 2 else b"")


def _data_tar(uid: int, gid: int) -> bytes:
    target = io.BytesIO()
    with tarfile.open(fileobj=target, mode="w:xz") as archive:
        member = tarfile.TarInfo("var/jb/usr/libexec/lumenboardd")
        member.size = 4
        member.mode = 0o755
        member.uid = uid
        member.gid = gid
        member.uname = "root"
        member.gname = "wheel"
        archive.addfile(member, io.BytesIO(b"test"))
    return target.getvalue()


def _write_deb(path: Path, uid: int, gid: int) -> None:
    path.write_bytes(
        b"!<arch>\n"
        + _ar_member("debian-binary", b"2.0\n")
        + _ar_member("data.tar.xz", _data_tar(uid, gid))
    )


class DebOwnershipVerifierTests(unittest.TestCase):
    def run_verifier(self, package: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(VERIFIER), str(package)],
            text=True,
            capture_output=True,
            check=False,
        )

    def test_accepts_numeric_root_owner_even_when_group_name_is_wheel(self):
        with tempfile.TemporaryDirectory() as directory:
            package = Path(directory) / "root-owned.deb"
            _write_deb(package, 0, 0)
            result = self.run_verifier(package)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("numeric owner 0:0", result.stdout)

    def test_rejects_host_builder_uid_and_gid_despite_root_wheel_names(self):
        with tempfile.TemporaryDirectory() as directory:
            package = Path(directory) / "host-owned.deb"
            _write_deb(package, 501, 20)
            result = self.run_verifier(package)
        self.assertEqual(result.returncode, 1)
        self.assertIn("uid=501 gid=20", result.stderr)

    def test_rejects_invalid_ar_header(self):
        with tempfile.TemporaryDirectory() as directory:
            package = Path(directory) / "invalid.deb"
            package.write_bytes(b"not a deb")
            result = self.run_verifier(package)
        self.assertEqual(result.returncode, 2)
        self.assertIn("not a Debian ar archive", result.stderr)


if __name__ == "__main__":
    unittest.main()