# Copyright (c) 2026 Niels Wieser, TU Darmstadt
# SPDX-License-Identifier: MIT

import os

# Paths (adjust to your local setup)
vc_file = "build/lowrisc_ibex_synthesis_system_0/lint-verilator/lowrisc_ibex_synthesis_system_0.vc"
tcl_output = "ibex_sources.tcl"

# Get the directory where the .vc file lives to resolve relative paths
vc_dir = os.path.dirname(os.path.abspath(vc_file))

files = []
includes = []
defines = []

if not os.path.exists(vc_file):
    print(f"Error: {vc_file} not found.")
    exit(1)

with open(vc_file, 'r') as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith('#'): continue
        
        if line.startswith('+incdir+'):
            path = line.replace('+incdir+', '')
            # Resolve to absolute path
            abs_path = os.path.abspath(os.path.join(vc_dir, path))
            includes.append(abs_path)
            
        elif line.startswith('+define+'):
            defines.append(line.replace('+define+', ''))
            
        elif line.endswith('.sv') or line.endswith('.v'):
            # Resolve to absolute path
            abs_path = os.path.abspath(os.path.join(vc_dir, line))
            files.append(abs_path)

# Sort: Packages first
pkgs = [f for f in files if "pkg" in f]
rtl = [f for f in files if "pkg" not in f]
sorted_files = pkgs + rtl

with open(tcl_output, 'w') as f:
    f.write(f"set search_path [list . \\\n")
    for inc in includes:
        f.write(f"  {inc} \\\n")
    f.write("]\n\n")

    f.write("set RTL_SOURCES [list \\\n")
    for s in sorted_files:
        f.write(f"  {s} \\\n")
    f.write("]\n\n")
    
    if defines:
        f.write("set RTL_DEFINES [list \\\n")
        for d in defines:
            f.write(f"  {d} \\\n")
        f.write("]\n")

print(f"Generated {tcl_output} with absolute paths.")