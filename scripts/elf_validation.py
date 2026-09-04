#!/usr/bin/env python3
"""Dependency-free structural validation for little-endian ELF64 programs."""

from __future__ import annotations

from pathlib import Path
import struct


ELF_HEADER_SIZE = 64
PROGRAM_HEADER_SIZE = 56
SECTION_HEADER_SIZE = 64
ET_EXEC = 2
ET_DYN = 3
PT_LOAD = 1
SHT_NOBITS = 8
PN_XNUM = 0xFFFF


def _range_fits(offset: int, length: int, file_size: int) -> bool:
    return 0 <= offset <= file_size and 0 <= length <= file_size - offset


def is_valid_elf_machine(path: Path, expected_machine: int) -> bool:
    try:
        file_size = path.stat().st_size
        with path.open("rb") as stream:
            header = stream.read(ELF_HEADER_SIZE)
            if len(header) != ELF_HEADER_SIZE:
                return False
            if header[:4] != b"\x7fELF" or header[4:7] != bytes((2, 1, 1)):
                return False
            fields = struct.unpack("<16sHHIQQQIHHHHHH", header)
            (
                _, elf_type, machine, version, _, program_offset,
                section_offset, _, header_size, program_entry_size,
                program_count, section_entry_size, section_count,
                section_name_index,
            ) = fields
            if (
                elf_type not in {ET_EXEC, ET_DYN}
                or machine != expected_machine
                or version != 1
                or header_size != ELF_HEADER_SIZE
                or program_count in {0, PN_XNUM}
                or program_entry_size < PROGRAM_HEADER_SIZE
                or program_offset < ELF_HEADER_SIZE
                or not _range_fits(
                    program_offset, program_entry_size * program_count, file_size
                )
            ):
                return False

            has_load_segment = False
            for index in range(program_count):
                stream.seek(program_offset + index * program_entry_size)
                program = stream.read(PROGRAM_HEADER_SIZE)
                if len(program) != PROGRAM_HEADER_SIZE:
                    return False
                (
                    program_type, _, file_offset, virtual_address, _, file_length,
                    memory_length, alignment,
                ) = struct.unpack("<IIQQQQQQ", program)
                if not _range_fits(file_offset, file_length, file_size):
                    return False
                if memory_length < file_length:
                    return False
                if alignment not in {0, 1} and alignment & (alignment - 1):
                    return False
                if (
                    program_type == PT_LOAD
                    and alignment > 1
                    and file_offset % alignment != virtual_address % alignment
                ):
                    return False
                has_load_segment |= program_type == PT_LOAD
            if not has_load_segment:
                return False

            if section_offset == 0:
                return section_count == 0 and section_name_index == 0
            if (
                section_offset < ELF_HEADER_SIZE
                or section_entry_size < SECTION_HEADER_SIZE
            ):
                return False

            actual_section_count = section_count
            if actual_section_count == 0:
                if not _range_fits(section_offset, SECTION_HEADER_SIZE, file_size):
                    return False
                stream.seek(section_offset)
                section_zero = stream.read(SECTION_HEADER_SIZE)
                actual_section_count = struct.unpack("<IIQQQQIIQQ", section_zero)[5]
            if actual_section_count == 0 or not _range_fits(
                section_offset,
                section_entry_size * actual_section_count,
                file_size,
            ):
                return False
            if (
                section_name_index not in {0, 0xFFFF}
                and section_name_index >= actual_section_count
            ):
                return False

            for index in range(actual_section_count):
                stream.seek(section_offset + index * section_entry_size)
                section = stream.read(SECTION_HEADER_SIZE)
                if len(section) != SECTION_HEADER_SIZE:
                    return False
                _, section_type, _, _, file_offset, length, _, _, alignment, _ = (
                    struct.unpack("<IIQQQQIIQQ", section)
                )
                if section_type != SHT_NOBITS and not _range_fits(
                    file_offset, length, file_size
                ):
                    return False
                if alignment not in {0, 1} and alignment & (alignment - 1):
                    return False
            return True
    except (OSError, struct.error, ValueError):
        return False
