#!/usr/bin/env python3
"""Use Libtool 2.5.4's existing C/C++ tags for Apple Objective-C commands.

Automake 1.18.1 generates untagged Objective-C compile/link commands,
including per-target commands that bypass LTOBJCCOMPILE. Patch all generated
logical Makefile lines, keeping their compiler, language flags and inputs.
"""
import pathlib
import re
import sys


def fix(text):
    # Include backslash continuations (e.g. LTOBJCCOMPILE and OBJCLINK).
    logical_lines = re.findall(r'(?:[^\n]*\\\n)*[^\n]*(?:\n|$)', text)
    changed = 0
    result = []
    for line in logical_lines:
        if '$(LIBTOOL)' in line and re.search(r'--mode=(?:compile|link)\b', line):
            if re.search(r'\$\(OBJCXX(?:LD)?\)', line):
                tag = 'CXX'
            elif re.search(r'\$\(OBJC(?:LD)?\)', line):
                tag = 'CC'
            else:
                result.append(line)
                continue
            if not re.search(r'--tag(?:=|\s)', line):
                line = line.replace('$(LIBTOOL)', '$(LIBTOOL) --tag=' + tag, 1)
                changed += 1
        result.append(line)
    return ''.join(result), changed


if __name__ == '__main__':
    total = 0
    for path in pathlib.Path(sys.argv[1]).rglob('Makefile'):
        # Contrib Makefiles may contain legacy-encoded comments. Preserve
        # every byte while editing only the ASCII libtool command syntax.
        text, count = fix(path.read_bytes().decode('latin-1'))
        if count:
            path.write_bytes(text.encode('latin-1'))
            print(f'{path}: tagged {count} Objective-C commands')
            total += count
    if not total:
        raise SystemExit('No untagged Objective-C commands found; review pinned build inputs')
    print(f'Tagged {total} Objective-C commands without changing compiler flags')
