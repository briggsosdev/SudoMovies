sub init()
    m.top.functionName = "RunFembox"
end sub

sub RunFembox()
    ' Any uncaught error here would kill the task thread at control="run" with
    ' no status event, so the caller's observer never fires and its progress
    ' overlay stays up forever (stuck Watch-now). try/catch guarantees a
    ' terminal status + control="stop" on every exit path.
    try
    ' NOTE: do NOT reset m.top.status here. With alwaysNotify="true" on
    ' the status field, writing 0 (the initial value) fires the observer
    ' immediately with zero candidates, and the handler consumes it before
    ' the real result arrives. Terminal states below always fire.
    if m.top.tmdbId = "" or m.top.token = "" then
        m.top.errorDetail = "Set your free Febbox token in Settings first."
        m.top.status = 400
        m.top.control = "stop"
        return
    end if

    if m.top.mediaType = "tv" then
        s = m.top.season
        e = m.top.episode
        if s = "" then s = "1"
        if e = "" then e = "1"
        url = _FemboxEpisodeUrl(m.top.tmdbId, s.ToInt(), e.ToInt(), m.top.token)
    else
        url = FemboxMovieUrl(m.top.tmdbId, m.top.token)
    end if
    res = HttpGetText(url, {})
    if res.status <> 200 then
        expired = FebboxTokenExpired(m.top.token)
        if res.status = 400 or res.status = 403 or res.status = 401 then
            if expired then
                m.top.errorDetail = "Febbox token expired. Re-paste a fresh token in Settings."
            else
                m.top.errorDetail = "Febbox rejected the token. Re-check it in Settings."
            end if
        else
            m.top.errorDetail = "Febbox API failed (HTTP " + res.status.ToStr() + ")."
        end if
        m.top.status = res.status
        m.top.control = "stop"
        return
    end if

    cands = FemboxParseCandidates(res.body)
    if cands.count() = 0 then
        m.top.errorDetail = "Febbox returned no usable links for this title."
        m.top.status = 204
        m.top.control = "stop"
        return
    end if

    ' Score by quality so the best playable option ranks first. The API
    ' returns ORG/4K first, but huge x265 files stall the decoder
    ' (flashing/white lines). Prefer 1080p/720p HLS for smooth playback.
    for each c in cands
        q = LCase(SafeStr(c, "quality", ""))
        lo = LCase(c.url)
        isHls = (Instr(1, lo, ".m3u8") > 0)
        sc = 0
        if Instr(1, q, "1080") > 0 then
            sc = 100
        else if Instr(1, q, "720") > 0 then
            sc = 90
        else if Instr(1, q, "480") > 0 then
            sc = 60
        else if Instr(1, q, "360") > 0 then
            sc = 40
        else if Instr(1, q, "4k") > 0 or Instr(1, q, "2160") > 0 or Instr(1, q, "org") > 0 then
            ' 4K and ORG remuxes are too heavy for reliable decode on this TV.
            sc = 10
        else
            sc = 50
        end if
        if isHls then
            sc = sc + 50
        end if
        c.score = sc
    end for
    RankCandidates(cands)
    for each c in cands
        lbl = "FEM"
        if c.quality <> "" and c.quality <> invalid then
            lbl = lbl + " " + c.quality
        end if
        lo = LCase(c.url)
        if Instr(1, lo, ".m3u8") > 0 then
            lbl = lbl + " HLS"
        else
            lbl = lbl + " MP4"
        end if
        if c.size <> "" and c.size <> invalid then
            lbl = lbl + " " + c.size
        end if
        c.label = lbl
    end for

    m.top.candidates = cands
    m.top.status = 200
    catch e
        ' Defensive message extraction (audit finding): a throw inside the
        ' catch would skip the terminal status write and strand the modal.
        m.top.errorDetail = "Febbox task error: " + TaskErrorText(e)
        m.top.status = 400
    end try
    m.top.control = "stop"
end sub

' e.Message may be missing/invalid on this firmware; never let the catch
' itself throw (pattern from LiveTvTaskErrorText).
function TaskErrorText(e as Dynamic) as String
    if e <> invalid and type(e) = "roAssociativeArray" and e.DoesExist("Message") then
        msg = e["Message"]
        if msg <> invalid and (type(msg) = "String" or type(msg) = "roString") and msg <> "" then
            return msg
        end if
    end if
    return "unexpected error"
end function