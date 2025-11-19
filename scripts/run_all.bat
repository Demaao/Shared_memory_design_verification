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

REM Loop over all test modes
for %%T in (%TESTS%) do (
    echo.
    echo --- Running simulation for TEST_MODE=%%T ---
    
    REM Replace TEST_MODE definition inside the testbench
    powershell -Command "(Get-Content %TB_FILE%) -replace 'parameter\s+string\s+TEST_MODE\s*=.*?;', 'parameter string TEST_MODE = \"%%T\";' | Set-Content %TB_FILE%"
    
    REM Compile RTL and testbench with include directories
    iverilog -I rtl -I tb -o sim_out -s tb_butterfly_network rtl\*.v tb\tb_butterfly_network.v
    
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
