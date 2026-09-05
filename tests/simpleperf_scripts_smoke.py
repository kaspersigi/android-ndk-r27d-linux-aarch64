#!/usr/bin/env python3
"""Run with AArch64 Python: exercise default discovery and real report CLIs."""

import json
import os
from pathlib import Path
import platform
import subprocess
import sys

ndk, record, output = (Path(value).resolve() for value in sys.argv[1:])
assert sys.platform == "linux" and platform.machine().lower() in ("aarch64", "arm64")
sys.path.insert(0, str(ndk / "simpleperf"))
from simpleperf_report_lib import ReportLib
from simpleperf_utils import ToolFinder, get_host_binary_path

library = ReportLib()  # Do not pass a library path: this is the regression gate.
try:
    library.SetRecordFile(str(record))
    samples = 0
    while library.GetNextSample():
        samples += 1
    assert samples == 2409, samples
finally:
    library.Close()

assert Path(get_host_binary_path("simpleperf")) == ndk / "simpleperf/bin/linux/aarch64/simpleperf"
for tool in ("llvm-readelf", "llvm-objdump", "llvm-symbolizer", "llvm-strip"):
    actual = ToolFinder.find_tool_path(tool, str(ndk))
    expected = ndk / "toolchains/llvm/prebuilt/linux-aarch64/bin" / tool
    assert actual is not None and Path(actual) == expected, (tool, actual)

output.mkdir(parents=True, exist_ok=True)
environment = dict(os.environ, PYTHONDONTWRITEBYTECODE="1", PYTHONIOENCODING="utf-8")
for script, filename in (("stackcollapse.py", "stacks.folded"),
                         ("gecko_profile_generator.py", "gecko.json"),
                         ("report_sample.py", "samples.txt")):
    with (output / filename).open("w", encoding="utf-8") as stream:
        subprocess.run([sys.executable, "-B", str(ndk / "simpleperf" / script), "-i", str(record)],
                       stdout=stream, env=environment, check=True)
    assert (output / filename).stat().st_size > 0, script

lines = (output / "stacks.folded").read_text(encoding="utf-8").splitlines()
assert all(line.rsplit(" ", 1)[1].isdigit() for line in lines)
profile = json.loads((output / "gecko.json").read_text(encoding="utf-8"))
assert profile["threads"] and sum(len(thread["samples"]["data"]) for thread in profile["threads"]) > 0
print("simpleperf-scripts-ok samples={} folded_stacks={} reports=3 llvm_tools=4".format(samples, len(lines)))
