"""Download the fixed Linux SDK artifacts; verify every byte before using them."""

import hashlib
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path
from urllib.request import urlopen

from json_boundary import objects, read_object, string


def main() -> None:
    lock = read_object(Path("/opt/haruka-ci/toolchain.lock.json"))
    with tempfile.TemporaryDirectory(prefix="haruka-sdk-") as directory:
        for artifact in objects(lock["artifacts"]):
            name = string(artifact["name"])
            target = Path(directory) / string(artifact["filename"])
            digest = hashlib.sha256()
            with (
                urlopen(string(artifact["url"]), timeout=120) as response,  # noqa: S310 - fixed reviewed HTTPS SDK URLs.
                target.open("wb") as output,
            ):
                while block := response.read(1024 * 1024):
                    output.write(block)
                    digest.update(block)
            if digest.hexdigest() != artifact["sha256"]:
                raise RuntimeError("SDK checksum mismatch: " + name)
            if artifact["kind"] == "wheel":
                subprocess.run(  # noqa: S603 - checksum-verified wheel with literal installer argv.
                    [
                        sys.executable,
                        "-m",
                        "pip",
                        "install",
                        "--no-deps",
                        "--no-index",
                        str(target),
                    ],
                    check=True,
                )
            else:
                with tarfile.open(target) as archive:
                    archive.extractall("/opt", filter="data")
            sys.stdout.write("Verified and installed " + name + "\n")
            sys.stdout.flush()


if __name__ == "__main__":
    main()
