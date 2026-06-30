#!/usr/bin/env python3

# Created by Diego Castro for the PPE support team
# This script uses a simple regex to remove internal information from reject logs

from colorama import Fore, Back, Style
import re
import sys


def usage():
    print(f"Usage: {sys.argv[0]} {Fore.RED}<input_file>{Fore.RESET} {Fore.GREEN}[output_file]{Fore.RESET}")

# Remove log entries matching the NOQUEUE pattern
# and write the cleaned content to the output file.
def remove_data():
    with open(input_file, 'r') as f:
        content = f.read()

        pattern = r'(eu|us).+NOQUEUE:\s'
        substitution = ''

        output = re.sub(pattern, substitution, content)

        with open(output_file, 'w') as f:
            f.write(output)

# Require at least an input filename
if len(sys.argv) < 2:
    usage()
    sys.exit(1)
elif len(sys.argv) == 2: # Prompt for an output filename if was not supplied
    input_file = sys.argv[1]
    output_file = input(f"{Fore.GREEN}Output filename:{Fore.RESET} ").strip().lower()
    remove_data()
# elif len(sys.argv) >= 3:
else:
    input_file = sys.argv[1]
    output_file = sys.argv[2]
    remove_data()