@echo off
REM ==========================================================
REM  Shared Memory Design Verification - Batch Automation
REM  Author: Dema Omar
REM  Purpose: Run all test modes (K=5) automatically
REM ==========================================================

setlocal enabledelayedexpansion

set TB_FILE=tb\tb_butterfly_network.v
set SIM_DIR=simulation
set TESTS=READ_ONLY WRITE_ONLY MIXED_RW SAME_ADDR_WRITES HASHED_READS

echo.
echo ======= Starting Automated Verification =======
echo.

for %%T in (%TESTS%) do (
    echo.
    echo --- Running simulation for TEST_MODE=%%T ---

    REM Compile RTL and testbench with macro define for current mode
    iverilog -I rtl -I tb -D%%T -o sim_out -s tb_butterfly_network rtl\*.v tb\tb_butterfly_network.v

    REM Run simulation and save log output
    vvp sim_out > %SIM_DIR%\simulation_K5_%%T.txt

    echo Simulation for %%T completed. Results saved to %SIM_DIR%\simulation_K5_%%T.txt
)

echo.
echo ======= All simulations completed. =======
echo Running Python analysis...
echo.

python analysis\analyze_results.py

echo.
echo ======= Analysis completed! =======
pause
