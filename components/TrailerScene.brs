' TrailerScene.brs - full-screen player for one YouTube video id.
'
' Opened by the Trailer helper (HomeScene scope), which sets videoId and
' observes "done". Teardown contract mirrors GenreScene: BACK and end of
' playback both funnel through TrailerClose(), which sets done = true and
' lets the parent remove this node.
'
' PLAYBACK: the bare id goes to a ContentNode's ifUrlSet - the firmware's
' documented way to hand a YouTube watch URL to a Video node. That needs no
' YouTube Data API key and no stream scraping (a scraped googlevideo URL
' expires within hours). There was no existing YouTube player in this
' codebase to reuse (no YouTube/ifUrlSet/roYouTube anywhere under
' components/), so this is the single new playback path; it reuses the
' project's only proven video setup - an XML-DECLARED Video node inside
' the component, per the LiveTvScene v7 note that runtime-created Video
' nodes play audio but render black on this firmware.
'
' SAFETY: a null/blank id never builds a ContentNode and never touches
' control, so there is no broken Video state to recover from - the screen
' just explains itself and waits for BACK.

sub init()
    m.video = m.top.findNode("trailerVideo")
    m.message = m.top.findNode("trailerMessage")
    m.captionBg = m.top.findNode("trailerCaptionBg")
    m.caption = m.top.findNode("trailerCaption")
    m.started = false
    m.closed = false
    if m.video <> invalid then
        m.video.observeField("state", "OnTrailerVideoState")
    end if
    ' Fields are assigned after CreateObject, so init only observes.
    m.top.observeField("videoId", "OnTrailerId")
    cap = m.top.titleText
    if cap <> invalid and cap <> "" then
        TrailerShowCaption(cap)
    end if
    ' A caller that already set videoId before this component existed still
    ' starts; the m.started guard below makes the double call harmless.
    id = m.top.videoId
    if id <> invalid and id <> "" then
        OnTrailerId(invalid)
    end if
end sub

sub OnTrailerId(msg as Object)
    if m.closed then return
    if m.started then return
    id = m.top.videoId
    if id = invalid then id = ""
    id = id.Trim()
    if id = "" then
        TrailerShowMessage("No trailer to play.")
        return
    end if
    if m.video = invalid then
        TrailerShowMessage("Trailer player is unavailable. Press BACK.")
        return
    end if
    content = CreateObject("roSGNode", "ContentNode")
    content.ifUrlSet = "http://www.youtube.com/watch?v=" + id
    cap = m.top.titleText
    if cap <> invalid and cap <> "" then content.title = cap
    m.started = true
    m.video.content = content
    m.video.visible = true
    m.video.setFocus(true)
    m.video.control = "play"
    TrailerShowMessage("")
    ? "TRAILER play id=" + id
end sub

sub OnTrailerVideoState(evt as Object)
    if m.closed then return
    state = evt.getData()
    if state = invalid then state = ""
    if type(state) <> "roString" and type(state) <> "String" then state = state.ToStr()
    ? "TRAILER state=" + state
    if state = "finished" then
        TrailerClose()
        return
    else if state = "error" then
        ' ifUrlSet can still be refused (age gate, region lock, a deleted
        ' upload). Say why and leave the screen up: BACK is then the only
        ' way out, and the parent gets a clean done.
        code = ""
        if m.video <> invalid then
            ec = m.video.errorCode
            if ec <> invalid then code = " (" + ec.ToStr() + ")"
        end if
        TrailerShowMessage("This trailer cannot be played" + code + ". Press BACK.")
    end if
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if m.closed then return false
    if key = "back" then
        TrailerClose()
        return true
    end if
    return false
end function

sub TrailerClose()
    if m.closed then return
    m.closed = true
    if m.video <> invalid then
        ' Unobserve FIRST: stopping releases the plane and re-fires
        ' "paused"/"finished" into a scene that is already closing, which
        ' is a render-thread re-entry (see the note in
        ' PlaybackScene.OnVideoState).
        m.video.unobserveField("state")
        m.video.control = "stop"
        m.video.content = invalid
        m.video.visible = false
    end if
    m.top.done = true
end sub

sub TrailerShowMessage(msg as String)
    if m.message = invalid then return
    m.message.text = msg
    m.message.visible = msg <> ""
end sub

sub TrailerShowCaption(t as String)
    if m.caption = invalid then return
    m.caption.text = t
    m.caption.visible = t <> ""
    if m.captionBg = invalid then return
    m.captionBg.visible = t <> ""
end sub
