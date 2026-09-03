#!/usr/bin/env python3
import ctypes
import sys


library_path, record_path = sys.argv[1:]
library = ctypes.CDLL(library_path)
library.CreateReportLib.restype = ctypes.c_void_p
library.DestroyReportLib.argtypes = [ctypes.c_void_p]
library.SetRecordFile.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
library.SetRecordFile.restype = ctypes.c_bool
library.GetNextSample.argtypes = [ctypes.c_void_p]
library.GetNextSample.restype = ctypes.c_void_p

handle = library.CreateReportLib()
assert handle
try:
    assert library.SetRecordFile(handle, record_path.encode())
    sample_count = sum(1 for _ in iter(lambda: library.GetNextSample(handle), None))
    assert sample_count == 2409, sample_count
    print(f"simpleperf-report-ok samples={sample_count}")
finally:
    library.DestroyReportLib(handle)
