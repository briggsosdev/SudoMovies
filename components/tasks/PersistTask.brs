' Off-thread registry persistence task.
'
' RETIRED 2026-09-23 (see Persist.brs header): this task was live for one
' build. The queue-via-field handoff froze the app at the first registry
' save on the target firmware, and with no console output on that device
' the failure was untriageable in place. Nothing instantiates this
' component anymore; if anything ever does, RunPersist deliberately does
' NOTHING (a no-op can never wipe or deadlock) — synchronous drains in
' Persist.brs are the only flush path.

sub init()
    m.top.functionName = "RunPersist"
end sub

sub RunPersist()
    m.top.control = "stop"
end sub
