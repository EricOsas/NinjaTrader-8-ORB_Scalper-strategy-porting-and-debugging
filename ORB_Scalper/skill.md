---
name: orb_scalper_knowledge
description: Provides architecture and development details for the ORB Scalper EA in MetaTrader 5.
---

# ORB Scalper EA Architecture & Knowledge

This skill provides the context needed to understand and modify the ORB Scalper Expert Advisor.

## Overview
The ORB (Opening Range Breakout) Scalper is an advanced MetaTrader 5 Expert Advisor that trades breakouts during specific session times (e.g., New York, London, Asian). It uses an intraday and daily/weekly range logic to capture momentum shifts.

## File Architecture
* **`ORB_Scalper.mq5`**: The core execution file. It includes:
  - Input definitions (Risk, Sessions, Trade Geometry, Range Slots).
  - Initialization (`OnInit`) and Deinitialization (`OnDeinit`) routines.
  - Tick processing (`OnTick`) and order execution logic.
* **`ORB_Dashboard.mqh`**: Contains the logic for the on-chart user interface. If you need to add or remove elements from the UI, you will modify this file.
* **`ORB_Notify.mqh`**: Manages user notifications, including push notifications, emails, and terminal print statements.
* **`ORB_Time.mqh`**: Handles all time-related logic. This is where session start/end times, cutoff minutes, and broker time offsets (e.g., Tokyo DST shifts) are calculated.
* **`ORB_Visuals.mqh`**: Handles chart objects such as drawing the Opening Range box, stop loss/take profit lines, and trailing stop indicators on the chart.

## Trade Management Logic
* **Risk & Capital**: Position sizing is determined based on balance, equity, or free margin, with options to include commission buffers.
* **Sessions**: Trading can be restricted to specific windows (NY, London, Asian) defined by an opening time and a cutoff period.
* **Trailing & Stops**: Supports continuous and step trailing. It also features a "Breakeven" mode to lock in spread and commission costs.

## Development Constraints
1. **MQL5 Syntax**: Always use modern MQL5 syntax (e.g., `CTrade` class for execution, robust `#include` directives).
2. **Compilation**: After any change, you must compile the project using `metaeditor64.exe` and ensure zero errors and warnings.
3. **Line Numbers**: The codebase is strictly maintained. Do not alter copyright headers without instruction.
4. **Caching**: MT5 caches inputs. When adding new input variables, ensure you note that users will need to reset the EA to see new default values.

When you are asked to modify the EA, refer to these structures to know exactly which file to alter.
