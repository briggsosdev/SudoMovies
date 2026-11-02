' Render-thread persistence queue.
'
' ProfilesSave/ConfigSave write through here instead of doing roRegistrySection
' writes synchronously on the render thread at every mutation: writes are
' coalesced into a single global queue keyed by (section,key), reads merge
' the queue (no stale read-after-write), and the queue is flushed
' SYNCHRONOUSLY by PersistDrain at every terminal point (the 9 drain sites:
' scene closes, toggles, profile ops, playback exit).
'
' 2026-09-23 ROLLBACK NOTE (post-freeze): this build briefly routed the
' queue through an off-thread PersistTask ("writes" field in / "flushed"
' field out). The first on-device run of that path froze the app at the
' exact moment of the first registry save (profile creation — the frozen
' repro: picker -> add profile -> DONE -> dead event loop), and the TV's
' console streams no prints, so the failure could not be triaged in place.
' Stopping a mid-flight registry-writing task and re-flushing the same
' section from the render thread is the prime suspect; regardless, the
' async path bought nothing (drain-at-terminal-points already guarantees
' durability — this was the audit's own recommended alternative). It is
' GONE: enqueue now only maintains the queue, flushes happen exclusively
' in PersistDrain, and PersistTask is never instantiated.
'
' Kept from the rework (the correctness fixes that did not add risk):
'   - Write() return checking in PersistDrain (registry quota visibility)
'   - ProfilesSave's FormatJson="" bail (PersistEnqueue treats "" as
'     DELETE, so an empty serialization must never be enqueued)
'   - queue merge in PersistReadRaw (reads reflect unsaved writes)

function PersistInit() as Object
    g = GetGlobalAA()
    if g = invalid then return invalid
    if g.PersistQueue = invalid then g.PersistQueue = []
    if g.PersistBusy = invalid then g.PersistBusy = false
    return g
end function

' Enqueue a registry write; coalesces by (section,key) so the latest value
' wins. An empty value means DELETE the key once flushed. Flushes happen in
' PersistDrain — call sites already drain at every terminal point.
sub PersistEnqueue(section as String, key as String, value as String)
    g = PersistInit()
    if g = invalid then return
    q = []
    if g.PersistQueue <> invalid then
        for each w in g.PersistQueue
            if w <> invalid and not (w.section = section and w.key = key) then
                q.Push(w)
            end if
        end for
    end if
    q.Push({ section: section, key: key, value: value })
    g.PersistQueue = q
end sub

' Read a registry value, preferring unflushed queued writes so reads always
' reflect the latest save even before the next drain.
function PersistReadRaw(section as String, key as String) as String
    g = GetGlobalAA()
    if g <> invalid and g.PersistQueue <> invalid then
        for each w in g.PersistQueue
            if w <> invalid and w.section = section and w.key = key then
                if w.value = invalid then return ""
                return w.value
            end if
        end for
    end if
    sec = CreateObject("roRegistrySection", section)
    v = sec.Read(key)
    if v = invalid then return ""
    return v
end function

' Synchronously write everything still queued (used right before a scene closes
' so no save is lost). Small number of writes; called only at terminal points.
sub PersistDrain()
    g = GetGlobalAA()
    if g = invalid then return
    q = []
    if g.PersistQueue <> invalid then
        q = g.PersistQueue
        g.PersistQueue = []
    end if
    for each w in q
        try
            if w <> invalid and w.section <> invalid and w.key <> invalid then
                sec = CreateObject("roRegistrySection", w.section)
                if w.value = invalid or w.value = "" then
                    sec.Delete(w.key)
                else
                    ok = sec.Write(w.key, w.value)
                    if ok <> true then
                        ? "PERSIST drain write failed section=" + w.section + " key=" + w.key + " (registry quota?)"
                    end if
                end if
                sec.Flush()
            end if
        catch e
        end try
    end for
    g.PersistBusy = false
end sub
