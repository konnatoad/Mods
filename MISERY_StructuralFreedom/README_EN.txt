MISERY STRUCTURAL FREEDOM v1.0.0
================================

WHAT THIS MOD DOES
------------------
Structural Freedom relaxes MISERY's structural-support checks so you can build layouts that the vanilla game rejects because there is not enough support directly below them.

This is NOT a true "build anywhere" / noclip building mod. It preserves the game's normal placement grid, collision, range, ownership and resource rules.

REQUIREMENTS
------------
- MISERY
- UE4SS

Vortex users can use the MISERY Vortex Extension, which supports UE4SS script mods.

INSTALLATION - VORTEX
---------------------
1. Make sure the MISERY Vortex Extension is installed/enabled.
2. Install this archive with Vortex.
3. Deploy mods.
4. Launch MISERY.

INSTALLATION - MANUAL
---------------------
1. Install UE4SS for MISERY.
2. Copy the folder "MISERY_StructuralFreedom" into:

   MISERY\Binaries\Win64\ue4ss\Mods\

3. The final path should contain:

   ...\ue4ss\Mods\MISERY_StructuralFreedom\scripts\main.lua
   ...\ue4ss\Mods\MISERY_StructuralFreedom\enabled.txt

4. Launch MISERY and load a save.

HOW IT BEHAVES / IMPORTANT LIMITATIONS
--------------------------------------
1. You still cannot place objects freely in empty air.
   The game must still find a real placement grid/location.

2. Walls are much less restricted by structural support, but they still need a valid place/grid to attach to. This mod does not turn wall placement into noclip/free positioning.

3. Floating floors require a temporary construction path.
   If MISERY does not give you a grid for the floor you want:
   - Build a temporary wall/support below.
   - Place the upper floor.
   - Remove the temporary wall/support afterward.
   The floor can remain after the temporary support is removed in tested cases.

4. Removing a lower wall may still destroy walls stacked above it.
   MISERY has separate destruction/dependency logic. Structural Freedom intentionally does NOT disable that system in v1.0.0.

5. Collision is still active.
   You cannot intentionally place pieces through solid objects just because Structural Freedom is installed.

6. Build costs, ownership and normal build distance are not intentionally changed.

DIAGNOSTICS
-----------
Open the UE4SS console (normally F10) and use:

   structuralfreedomstatus

Expected installed state:

   grid=true sgk=true

If either says false after loading a save, run:

   structuralfreedominstall

Legacy test commands "freebuildstatus" and "freebuildinstall" are also kept as aliases.

STABILITY / SAVE WARNING
------------------------
Version 1.0.0 is based on the stability-tested 0.2.2 branch.
It has been tested with repeated saving/loading, unusual unsupported structures, and a basic multiplayer session without an observed repeatable crash in the final architecture.

Still:
- Back up important saves before installing any gameplay mod.
- Future MISERY updates may change internal Blueprint functions and require a mod update.
- If MISERY updates and you suddenly get crashes or the mod stops working, disable Structural Freedom first and check for an updated version.
- Avoid removing the mod in the middle of an important unsupported build without making a backup first; vanilla MISERY may reevaluate structural dependencies when pieces are edited/destroyed.

MULTIPLAYER
-----------
A basic multiplayer session was tested without an observed crash. Multiplayer behavior has NOT been exhaustively validated for every host/client configuration.

CREDITS / IMPLEMENTATION
------------------------
Built as an independent UE4SS Lua mod for MISERY.
No code or assets from Not so Miserable are included in this archive.
The implementation was developed from MISERY runtime/object-dump information and UE4SS APIs.
