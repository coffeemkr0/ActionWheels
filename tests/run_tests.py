"""Run the Lua logic tests under Lua 5.1 (pip install lupa)."""
import subprocess
import sys
from lupa.lua51 import LuaRuntime

if subprocess.call([sys.executable, "tests/check_defined.py"]) != 0:
    sys.exit(1)

lua = LuaRuntime(unpack_returned_tuples=True)
try:
    lua.execute(open("tests/test_logic.lua").read())
except Exception as e:  # noqa
    print(e)
    sys.exit(1)
