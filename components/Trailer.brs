' Trailer.brs - the one entry point for "play this title's trailer".
'
' HomeScene already owns the child-scene lifecycle (ShowSeriesDetails /
' OnSeriesSceneDone, ShowGenreScreen / OnGenreSceneDone, CleanupChild); this
' file only adds the trailer-specific middle step, which HAS to be
' asynchronous because roURLTransfer can only be created on a Task thread:
'
'   TrailerOpen(rec) -> YoutubeTask -> TrailerOpenScene(videoId)
'                                     -> TrailerScene (observes "done")
'
' State is m.trailerTask / m.trailerScene / m.trailerTitle, mirroring the
' existing m.seriesScene and m.genreGroup handling. HomeInitReal initialises
' those three and names TrailerDone as the "done" observer; this file never
' assumes anything else about HomeScene.
'
' The details option entry is "Play trailer" (see DetailsEntries) and is
' driven by LABEL, not index, so the list can grow without breaking
' OnDetailsOptionSelected.

' Entry point: resolve and play the trailer for one TMDB record.
sub TrailerOpen(rec as Object)
    if rec = invalid then
        ShowToast("Nothing to play a trailer for")
        return
    end if
    ' Only real TMDB titles have a trailer to look up; a hand-edited
    ' registry row or a "Next page" tile has no id.
    if SafeStr(rec, "tmdbId", "") = "" then
        ShowToast("No trailer for this tile")
        return
    end if
    ' One trailer at a time: an in-flight lookup is abandoned and any
    ' already-open player is torn down before a new one opens.
    TrailerStopTask()
    TrailerCloseScene()
    task = CreateObject("roSGNode", "YoutubeTask")
    if task = invalid then
        ShowToast("Trailer is not available")
        return
    end if
    m.trailerTask = task
    task.observeField("status", "TrailerOnStatus")
    task.tmdbId = SafeStr(rec, "tmdbId", "")
    task.mediaType = TrailerMediaType(rec)
    task.title = SafeStr(rec, "title", "")
    task.trailerKey = TrailerRecordKey(rec)
    ' A Video node cannot play a youtube.com URL, so the task deep-links into
    ' the Roku YouTube app (ECP) once it has the id.
    task.launch = true
    if m.cfg <> invalid then
        task.tmdbKey = SafeStr(m.cfg, "tmdbKey", "")
    end if
    m.trailerTitle = SafeStr(rec, "title", "")
    ? "TRAILER lookup tmdb=" + task.tmdbId + " type=" + task.mediaType
    ShowToast("Looking up trailer...")
    task.control = "run"
end sub

' A result for an ABANDONED lookup must never open a player: the event is
' dropped unless it came from the current task.
' NODE COMPARISON RULE: `=`/`<>` on two nodes throws &h18 on this firmware -
' invalid-check first, then isSameNode().
sub TrailerOnStatus(evt as Object)
    src = invalid
    if evt <> invalid then src = evt.getRoSGNode()
    if src = invalid then return
    current = m.trailerTask
    if current = invalid then return
    if not src.isSameNode(current) then return
    TrailerStopTask()
    st = src.status
    if st = invalid then st = 0
    vid = src.videoId
    if vid = invalid then vid = ""
    detail = ""
    if src.errorDetail <> invalid then detail = src.errorDetail
    if st <> 200 or vid = "" then
        ? "TRAILER miss status=" + st.ToStr() + " detail=" + detail
        if detail = "" then detail = "No trailer for this title."
        ShowToast(detail)
        return
    end if
    ' The task already launched YouTube; this app is about to be backgrounded.
    ShowToast("Opening trailer in YouTube...")
end sub

sub TrailerOpenScene(videoIdIn as String, titleIn as String)
    if videoIdIn = invalid or videoIdIn = "" then
        ShowToast("No trailer for this title.")
        return
    end if
    TrailerCloseScene()
    scene = CreateObject("roSGNode", "TrailerScene")
    if scene = invalid then
        ShowToast("Trailer is not available")
        return
    end if
    scene.videoId = videoIdIn
    if titleIn <> invalid and titleIn <> "" then
        scene.titleText = titleIn
    end if
    scene.observeField("done", "TrailerDone")
    m.trailerScene = scene
    m.top.appendChild(scene)
    scene.setFocus(true)
end sub

' BACK inside the player, or the trailer finished: both arrive through the
' scene's "done" field, so there is exactly one teardown path (the same
' shape as OnSeriesSceneDone / OnGenreSceneDone).
sub TrailerDone()
    TrailerCloseScene()
    ' The details overlay is still up underneath, so give the options list
    ' its focus back instead of the home rows.
    if m.detailsList <> invalid then
        m.detailsList.setFocus(true)
    else if m.rows <> invalid then
        m.rows.setFocus(true)
    end if
end sub

sub TrailerCloseScene()
    if m.trailerScene <> invalid then
        CleanupChild(m.trailerScene)
        m.trailerScene = invalid
    end if
end sub

sub TrailerStopTask()
    if m.trailerTask <> invalid then
        m.trailerTask.control = "stop"
        m.trailerTask = invalid
    end if
end sub

function TrailerMediaType(rec as Object) as String
    if LCase(SafeStr(rec, "mediaType", "movie")) = "tv" then
        return "tv"
    end if
    return "movie"
end function

' A YouTube key the record already carries - costs no request. TMDB hands
' one out in videos.results[].key; nothing in Tmdb.brs keeps it today, but
' if a normalize ever does, the task returns it with zero network calls.
function TrailerRecordKey(rec as Object) as String
    for each k in ["trailerKey", "videoId", "trailerId", "youtubeKey"]
        v = SafeStr(rec, k, "")
        if v <> "" then return v
    end for
    return ""
end function
