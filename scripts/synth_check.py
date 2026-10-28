"""Technology-independent structural check; this does not produce lab PPA."""
from pathlib import Path
import json
from run_tests import ROOT, SOURCES, tool, run
import os

build=ROOT/"build/synth_check"
build.mkdir(parents=True,exist_ok=True)
yosys=tool("yosys")
if not yosys:
    raise SystemExit("Yosys not found; set EDA_OSS_CAD_SUITE.")
env=dict(os.environ)
suite=Path(yosys).parent.parent
env["PATH"]=os.pathsep.join([str(suite/"bin"),str(suite/"lib"),env.get("PATH","")])
paths=" ".join('"'+str(p).replace('\\','/')+'"' for p in SOURCES)
script=f'''read_verilog {paths}
hierarchy -check -top transformer_top
proc
check -assert
select -assert-none t:$dlatch
memory_collect
opt
check -assert
stat
write_json design.json
'''
(build/"check.ys").write_text(script,encoding="ascii")
run([yosys,"-s","check.ys"],build,env,build/"yosys.log")
design=json.loads((build/"design.json").read_text())
cells={}
for module in design["modules"].values():
    for cell in module.get("cells",{}).values():
        cells[cell["type"]]=cells.get(cell["type"],0)+1
(build/"summary.json").write_text(json.dumps({"status":"PASS","scope":"hierarchy, processes, no latches, drivers; unmapped default configuration","cell_types":cells},indent=2))
print("PASS: hierarchy, driver checks and no inferred latches. Not technology-mapped PPA.")
