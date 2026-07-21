# ORB Scalper Agent Guidelines

This file contains rules and guidelines for working on the ORB Scalper EA. 

## Project Structure
- `ORB_Scalper.mq5`: The main Expert Advisor file containing the `OnInit`, `OnTick`, and `OnDeinit` event handlers, as well as the core trading logic.
- `ORB_Dashboard.mqh`: Contains functions for rendering the on-chart UI dashboard.
- `ORB_Notify.mqh`: Handles push, email, and print notifications.
- `ORB_Time.mqh`: Contains logic for session timings (NY, London, Asian) and range window calculations.
- `ORB_Visuals.mqh`: Manages chart objects, drawing range boxes, and trailing stop lines.

## Compilation Rule
Whenever you make a change to the source code, you must compile the EA and ensure there are 0 errors and 0 warnings.
The default MT5 terminal compiler should be used.

**Command to compile:**
```powershell
Start-Process "C:\Program Files\MetaTrader 5\metaeditor64.exe" -ArgumentList "/compile:ORB_Scalper.mq5", "/log:build.log" -Wait
Get-Content build.log
```

If there are any errors or warnings in the `build.log`, you MUST address them and recompile until the log shows `0 errors, 0 warnings`.

## Modification Workflow
1. Read the relevant `.mqh` or `.mq5` files to understand the current logic.
2. Make your modifications.
3. Run the compilation command.
4. Read the `build.log`.
5. Fix errors and warnings.
6. Verify successful compilation.
