#!/usr/bin/env python3
"""Regression cases modeled on Automake 1.18.1 generated commands."""
from pathlib import Path
import runpy
import unittest
import tempfile
import subprocess
import sys

fix = runpy.run_path(str(Path(__file__).with_name('fix-apple-libtool-tags.py')))['fix']


class TagTests(unittest.TestCase):
    def test_compile_link_and_target_flags(self):
        source = ('LTOBJCCOMPILE = $(LIBTOOL) $(AM_V_lt) $(AM_LIBTOOLFLAGS) \\\n'
                  '\t$(LIBTOOLFLAGS) --mode=compile $(OBJC) $(DEFS) $(OBJCFLAGS)\n'
                  '\t$(LIBTOOL) $(AM_V_lt) --mode=compile $(OBJC) $(target_OBJCFLAGS) -c -o $@ $<\n'
                  'OBJCLINK = $(LIBTOOL) --mode=link $(OBJCLD) $(OBJCFLAGS)\n'
                  'OBJCXXLINK = $(LIBTOOL) --mode=link $(OBJCXXLD) $(OBJCXXFLAGS)\n'
                  '\t$(LIBTOOL) --tag=CC --mode=compile $(CC) $(CFLAGS)\n')
        result, count = fix(source)
        self.assertEqual(count, 4)
        self.assertIn('--tag=CXX --mode=link $(OBJCXXLD)', result)
        self.assertEqual(result.count('--tag=CC'), 4)
        # Removing only the newly added tags recovers every original byte.
        self.assertEqual(result.replace('$(LIBTOOL) --tag=CXX', '$(LIBTOOL)').replace(
            '$(LIBTOOL) --tag=CC', '$(LIBTOOL)', 3), source)
        self.assertEqual(fix(result), (result, 0))

    def test_non_utf8_makefile_bytes_preserved(self):
        original = b"# legacy comment: \xfc\xff\n$(LIBTOOL) --mode=compile $(OBJC)\n"
        with tempfile.TemporaryDirectory() as directory:
            makefile = Path(directory) / 'Makefile'
            makefile.write_bytes(original)
            subprocess.run([sys.executable, str(Path(__file__).with_name(
                'fix-apple-libtool-tags.py')), directory], check=True, capture_output=True)
            self.assertEqual(makefile.read_bytes(), original.replace(
                b'$(LIBTOOL)', b'$(LIBTOOL) --tag=CC'))

    def test_other_commands_untouched(self):
        for source in ['hello\n', '', 'CC = clang\n', '$(LIBTOOL) --mode=compile $(CC)\n']:
            self.assertEqual(fix(source), (source, 0))


if __name__ == '__main__':
    unittest.main()
