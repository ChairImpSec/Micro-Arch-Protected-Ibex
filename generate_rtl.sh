# Copyright (c) 2026 Niels Wieser, TU Darmstadt
# SPDX-License-Identifier: MIT

fusesoc --cores-root=. run --target=lint --setup lowrisc:ibex:synthesis_system
python3 vc_to_tcl.py