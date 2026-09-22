"""Execute the reviewed fixed Linux development test list with real node outcomes."""

import argparse
import json
import sys
import unittest
from pathlib import Path

from json_boundary import read_object, strings

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from scripts.quality.unittest_runner import (  # noqa: E402 - explicit test harness checkout.
    RecordedResult,
    flatten,
)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    nodes = strings(read_object(ROOT / "dev/ci/execution_matrix.json")["unittest"])
    if not nodes or args.output.exists():
        raise ValueError("Tests must be nonempty and evidence must be new")
    loader = unittest.TestLoader()
    suite = loader.loadTestsFromNames(nodes)
    actual = [test.id() for test in flatten(suite)]
    if loader.errors or sorted(actual) != sorted(nodes):
        raise ValueError("Required development test nodes not collected")
    result = RecordedResult()
    suite.run(result)
    passed = (
        result.wasSuccessful()
        and set(result.statuses) == set(nodes)
        and all(status == "passed" for status in result.statuses.values())
    )
    args.output.write_text(
        json.dumps({"passed": passed, "nodes": result.statuses}, indent=2) + "\n"
    )
    raise SystemExit(0 if passed else 1)


if __name__ == "__main__":
    main()
