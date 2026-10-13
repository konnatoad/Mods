-- View Debug settings. Copy this file to config.lua (in the same folder)
-- and change what you like; `git pull` never touches config.lua.
return {
    -- How often .view rec reads the angles, in milliseconds (16 = about 60 a second)
    sampleMs = 16,

    -- How often the on-screen readout (.view hud) updates, in milliseconds
    hudMs = 100,

    -- A recording stops by itself after this many seconds (at most 600)
    maxSeconds = 60,

    -- How many seconds .view buffer keeps (at most 60)
    bufferSeconds = 25,

    -- Hotkey that marks the moment the view sticks: saves the buffer, or marks
    -- a recording. "" = no hotkey (use .view dump / .view mark). A UE4SS key
    -- name like "F12" turns it on (F11 is the game's fullscreen key)
    markKey = "",
}
