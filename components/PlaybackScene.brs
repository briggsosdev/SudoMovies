sub init()
    m.errorGroup = m.top.findNode("errorGroup")
    m.errorLabel = m.top.findNode("errorLabel")
    m.errorList = m.top.findNode("errorList")
    m.resolveGroup = m.top.findNode("resolveGroup")
    m.resolveLabel = m.top.findNode("resolveLabel")
    m.resolveHint = m.top.findNode("resolveHint")
    m.pickerGroup = m.top.findNode("pickerGroup")
    m.pickerList = m.top.findNode("pickerList")
    if m.pickerList <> invalid then
        m.pickerList.observeField("itemSelected", "OnTvSourcePicked")
    end if
    m.tvCandidates = []
    m.cfg = ConfigLoad()
    m.started = false
    m.stopped = false
    m.pendingTask = invalid
    m.femTask = invalid
    m.vixTask = invalid
    m.pendingRec = invalid
    m.femRetries = 0
    m.triedTvVix = false
    m.closed = false
    m.video = invalid
    m.profiles = invalid
    m.profileId = ""
    m.saveMeta = invalid
    m.existingResume = invalid
    m.resumePrompt = invalid
    m.resumeList = invalid
    m.resumePos = 0
    m.promptOpen = false
    m.resumeCleared = false
    m.lastSaveSec = -100
    m.lastFemError = ""
    m.nextUpGroup = invalid
    m.nextUpList = invalid
    m.nextUpTask = invalid
    m.nextUpRec = invalid
    m.nextUpTimer = invalid
    m.nextUpCount = 0
    m.nextUpEpLabel = ""
    m.top.observeField("movie", "OnMovieSet")
    if m.errorList <> invalid then
        content = CreateObject("roSGNode", "ContentNode")
        nd = content.createChild("ContentNode")
        nd.title = "Retry"
        nd = content.createChild("ContentNode")
        nd.title = "Back"
        m.errorList.content = content
        m.errorList.observeField("itemSelected", "OnErrorPicked")
    end if
end sub

sub OnMovieSet()
    StartPlayback()
end sub

sub StartPlayback()
    if m.started then return
    m.started = true

    movie = m.top.movie
    if movie = invalid then
        ShowError("Nothing to play. Press BACK and pick another title.")
        return
    end if

    if SafeStr(movie, "url", "") <> "" then
        StartVideo(movie)
        return
    end if

    if SafeStr(movie, "url", "") <> "" then
        StartVideo(movie)
        return
    end if

    if SafeStr(movie, "mediaType", "") = "tv" and SafeStr(movie, "tmdbId", "") <> "" then
        ResolveEpisode(movie)
        return
    end if

    ShowError("This title has no stream URL. Press BACK and try another.")
end sub

' ------------------------------------------------------------------
' TV episode branch: resolve a stream for season/episode before playing
' ------------------------------------------------------------------

sub ResolveEpisode(rec as Object)
    m.pendingRec = rec
    m.femRetries = 0
    m.triedTvVix = false
    m.tryFebAfterVix = false
    m.lastResolver = ""
    ' Prefer the resolver that worked last time (Vix or Feb) so auto-play
    ' next episode reuses the user's choice.
    if m.lastResolver = "vix" then
        m.tryFebAfterVix = true
        TryTvVixSrc()
    else
        TryTvFembox()
    end if
end sub

sub TryTvFembox()
    if m.stopped then return
    token = FebboxGetActiveToken(m.cfg)
    if token = "" then
        FailTvResolve("No stream backends are configured. Add your free Febbox token in Settings to enable playback.")
        return
    end if
    ShowResolve("Asking Febbox for " + SafeStr(m.pendingRec, "title", "") + "...")
    task = CreateObject("roSGNode", "FemboxTask")
    task.tmdbId = SafeStr(m.pendingRec, "tmdbId", "")
    task.mediaType = "tv"
    task.season = SafeStr(m.pendingRec, "season", "1")
    task.episode = SafeStr(m.pendingRec, "episode", "1")
    task.token = token
    task.observeField("status", "OnTvFemboxStatus")
    m.femTask = task
    task.control = "run"
end sub

sub StampTvCand(cand as Object)
    cand.title = SafeStr(m.pendingRec, "title", "")
    cand.tmdbId = SafeStr(m.pendingRec, "tmdbId", "")
    cand.mediaType = "tv"
    cand.season = SafeStr(m.pendingRec, "season", "1")
    cand.episode = SafeStr(m.pendingRec, "episode", "1")
    cand.poster = SafeStr(m.pendingRec, "poster", "")
end sub

sub OnTvFemboxStatus()
    if m.stopped then return
    task = m.femTask
    m.femTask = invalid
    if task = invalid then return
    if task.errorDetail <> invalid and task.errorDetail <> "" then
        m.lastFemError = task.errorDetail
    end if
    if task.status = 200 and task.candidates <> invalid then
        for each c in task.candidates
            if type(c) = "roAssociativeArray" then
                StampTvCand(c)
                m.tvCandidates.Push(c)
            end if
        end for
        if task.candidates.count() > 0 then
            m.lastResolver = "feb"
        end if
    end if

    ' Quota/rejection codes rotate to the next saved Febbox token and retry,
    ' mirroring the HomeScene/EpisodeScene retry policy. Also retry when a
    ' 200 came back with nothing new to append.
    if ((task.status = 401 or task.status = 403 or task.status = 400 or task.status = 429 or task.status = 204) or (task.status = 200 and m.tvCandidates.count() = 0)) and m.cfg.febboxTokens <> invalid and m.femRetries < m.cfg.febboxTokens.count() then
        m.femRetries = m.femRetries + 1
        nextToken = FebboxRotateToken(m.cfg)
        if nextToken <> "" then
            TryTvFembox()
            return
        end if
    end if

    ' Febbox settled (with or without candidates): collect VixSrc too so the
    ' user gets a chooser instead of an auto-play.
    TryTvVixSrc()
end sub

sub TryTvVixSrc()
    if m.stopped then return
    if m.triedTvVix then
        FailTvResolve("Could not resolve this episode. Try another, or press BACK.")
        return
    end if
    m.triedTvVix = true
    ShowResolve("Asking VixSrc for " + SafeStr(m.pendingRec, "title", "") + "...")
    task = CreateObject("roSGNode", "VixSrcTask")
    task.tmdbId = SafeStr(m.pendingRec, "tmdbId", "")
    task.mediaType = "tv"
    task.season = SafeStr(m.pendingRec, "season", "1")
    task.episode = SafeStr(m.pendingRec, "episode", "1")
    task.observeField("status", "OnTvVixSrcStatus")
    m.vixTask = task
    task.control = "run"
end sub

sub OnTvVixSrcStatus()
    if m.stopped then return
    task = m.vixTask
    m.vixTask = invalid
    if task = invalid then return
    if task.status = 200 and task.candidates <> invalid then
        for each c in task.candidates
            if type(c) = "roAssociativeArray" then
                StampTvCand(c)
                m.tvCandidates.Push(c)
            end if
        end for
    end if
    ' Track last successful resolver for next-episode auto-play.
    if task.status = 200 and task.candidates <> invalid and task.candidates.count() > 0 then
        m.lastResolver = "vix"
    end if
    if m.tryFebAfterVix then
        m.tryFebAfterVix = false
        TryTvFembox()
    else
        ShowTvPicker()
    end if
end sub

sub ShowTvPicker()
    HideResolve()
    if m.tvCandidates.count() = 0 then
        FailTvResolve("Could not resolve this episode. Try another, or press BACK.")
        return
    end if
    content = CreateObject("roSGNode", "ContentNode")
    for each cand in m.tvCandidates
        nd = content.createChild("ContentNode")
        label = SafeStr(cand, "label", "")
        if label = "" then label = "Source"
        if cand.subtitles <> invalid and cand.subtitles.count() > 0 then
            label = label + "   (S)"
        end if
        nd.title = label
    end for
    if m.pickerList <> invalid then
        m.pickerList.content = content
    end if
    if m.pickerGroup <> invalid then
        m.pickerGroup.visible = true
        m.top.setFocus(true)
        if m.pickerList <> invalid then
            m.pickerList.setFocus(true)
        end if
    end if
end sub

sub HideTvPicker()
    if m.pickerGroup <> invalid then
        m.pickerGroup.visible = false
    end if
end sub

sub OnTvSourcePicked(msg as Object)
    if m.pickerList = invalid then return
    index = m.pickerList.itemSelected
    if index = invalid or index < 0 then return
    if m.tvCandidates = invalid or index >= m.tvCandidates.count() then return
    cand = m.tvCandidates[index]
    if type(cand) <> "roAssociativeArray" then return
    ' Keep the picker nodes alive: next-episode auto-advance resolves again
    ' in this same scene and ShowTvPicker reuses m.pickerList.
    HideTvPicker()
    StartVideo(cand)
end sub

sub ShowResolve(msg as String)
    if m.resolveLabel <> invalid then
        m.resolveLabel.text = msg
    end if
    if m.resolveGroup <> invalid then
        m.resolveGroup.visible = true
    end if
    m.top.setFocus(true)
end sub

sub HideResolve()
    if m.resolveGroup <> invalid then
        m.resolveGroup.visible = false
    end if
end sub

sub FailTvResolve(msg as String)
    HideResolve()
    if Instr(1, LCase(m.lastFemError), "expired") > 0 then
        ShowError("Febbox token expired - re-paste a fresh one in Settings.")
        return
    end if
    ShowError(msg)
end sub

sub ShowError(msg as String)
    if m.errorLabel <> invalid then
        m.errorLabel.text = msg
        m.errorLabel.visible = true
    end if
    if m.errorGroup <> invalid then
        m.errorGroup.visible = true
    end if
    if m.errorList <> invalid then
        m.errorList.setFocus(true)
    else
        m.top.setFocus(true)
    end if
end sub

sub OnErrorPicked()
    if m.errorList = invalid then return
    idx = m.errorList.itemSelected
    if idx = 0 then
        RetryPlayback()
    else
        ClosePlayback()
    end if
end sub

' Retry after an error: tear down any half-state and restart the resolve/play
' chain from the original movie. Safe when no video was ever created (resolve
' errors) or when one was removed after a decode failure.
sub RetryPlayback()
    if m.stopped or m.closed then return
    m.closed = false
    m.started = false
    m.resumeCleared = false
    m.resumePrompt = invalid
    m.resumeList = invalid
    m.promptOpen = false
    RemoveVideo()
    HideError()
    StartPlayback()
end sub

sub HideError()
    if m.errorGroup <> invalid then
        m.errorGroup.visible = false
    end if
    if m.errorLabel <> invalid then
        m.errorLabel.visible = false
    end if
end sub

' ------------------------------------------------------------------
' Video start. Movies arrive already-resolved (a "cand" with a URL);
' the TV branch builds the same shape above before calling this.
' ------------------------------------------------------------------

sub StartVideo(movie as Object)
    if movie = invalid or SafeStr(movie, "url", "") = "" then
        ShowError("No playable stream. Press BACK and try another source.")
        return
    end if

    ' Resume identity: prefer the interface resumeRec (set before .movie),
    ' fall back to keys carried on the candidate itself.
    m.saveMeta = ProfilesMetaForRec(m.top.resumeRec, movie)
    m.profiles = ProfilesLoad()
    m.profileId = ProfilesGetActiveId(m.profiles)
    m.existingResume = invalid
    m.resumeCleared = false
    if m.profileId <> "" and m.saveMeta.tmdbId <> "" then
        m.existingResume = ProfilesGetResume(m.profiles, m.profileId, m.saveMeta)
    end if

    content = CreateObject("roSGNode", "ContentNode")
    content.url = movie.url

    fmt = SafeStr(movie, "type", "")
    if fmt = "" or fmt = invalid then
        fmt = SafeStr(movie, "format", "")
    end if
    if LCase(fmt) = "hls" then
        content.streamFormat = "hls"
    end if

    ' Panel guard (1080p SDR Hisense): the Febbox CDN labels one URL
    ' "1080p" but that HLS master sometimes contains ONLY a 4K HDR
    ' variant (3840x2076, hev1, VIDEO-RANGE=PQ, ~9 Mbps). With no ABR
    ' cap the firmware plays it (state=playing, code=0) and the TV
    ' drops into its HDR picture mode -- which keeps its own
    ' picture-size/overscan memory -- so the picture looks zoomed/
    ' cropped with the scope letterbox reduced to a top bar while all
    ' SceneGraph UI stays 1:1. Roku forbids mixing HDR and SDR
    ' variants in one HLS manifest and gates HDR on an HDR10 display
    ' (roDeviceInfo.GetDisplayProperties().hdr10), so on a non-HDR
    ' panel cap the HLS ladder to SDR 1080p: 1080p tops out ~5.8 Mbps
    ' per the Roku ladder, the HDR variant runs ~9 Mbps.
    isHls = (LCase(fmt) = "hls")
    if isHls then
        content.switchingStrategy = "full-adaptation"
        canHdr = false
        try
            di = CreateObject("roDeviceInfo")
            dp = di.GetDisplayProperties()
            if dp <> invalid and dp.hdr10 = true then
                canHdr = true
            end if
        catch e
        end try
        if not canHdr then
            content.maxBandwidth = 8000
            content.adaptiveMaxStartBitrate = 4000
        end if
    end if

    title = SafeStr(movie, "title", "")
    if title <> "" then
        content.title = title
    end if

    headers = SafeGet(movie, "headers", invalid)
    if headers <> invalid and headers.count() > 0 then
        content.httpHeaders = headers
    end if

    ' Sideloaded subtitle tracks (srt/ttml/dfxp from OpenSubtitles etc.)
    ' show up in the player's built-in closed caption picker.
    subs = SafeGet(movie, "subtitles", [])
    if subs <> invalid and subs.count() > 0 then
        tracks = []
        for each s in subs
            track = {}
            track.TrackName = s.url
            if s.label <> invalid and s.label <> "" then
                track.Description = s.label
            else
                track.Description = "Subtitles"
            end if
            if s.lang <> invalid and s.lang <> "" then
                track.Language = s.lang
            end if
            tracks.push(track)
        end for
        content.subtitleTracks = tracks
    end if

    video = CreateObject("roSGNode", "Video")
    video.id = "videoPlayer"
    video.content = content
    ' Exact 1:1 on the 1080p panel: no GPU scaling, so no resampling
    ' artifacts (flickering/vertical lines) during playback.
    video.width = 1920
    video.height = 1080
    video.translation = [0, 0]
    ' Tell the firmware this 1080p SDR panel only needs a 1080p
    ' decode: a 3840x2076 HEVC variant otherwise decodes then
    ' downscales in the video plane while the UI stays 1:1.
    ' Guarded: field is firmware-gated; assigning an unknown SG field crashes.
    ' https://developer.roku.com/dev/docs/ifsgnodefield (hasField)
    if video.hasField("maxVideoDecodeResolution") then
        video.maxVideoDecodeResolution = [1920, 1080]
    end if
    video.enableTrickPlay = true
    video.enableUI = true
    m.video = video
    m.top.appendChild(video)
    video.observeField("state", "OnVideoState")
    video.observeField("streamingSegment", "OnStreamingSegment")
    video.observeField("position", "OnVideoPosition")
    video.setFocus(true)
    video.control = "play"
    MaybeShowResumePrompt()
end sub

' ------------------------------------------------------------------
' Resume prompt + per-profile position saving
' ------------------------------------------------------------------

sub MaybeShowResumePrompt()
    if m.existingResume = invalid then return
    p = ProfilesInt(m.existingResume, "p", 0)
    d = ProfilesInt(m.existingResume, "d", 0)
    if p < 10 then return
    if d > 0 and p / d >= 0.95 then return
    m.resumePos = p
    ShowResumePrompt(p)
end sub

sub ShowResumePrompt(posSec as Integer)
    if m.resumePrompt <> invalid then return
    g = CreateObject("roSGNode", "Rectangle")
    g.color = "0x000000E6"
    g.width = 1920
    g.height = 1080
    g.translation = "[0,0]"

    card = CreateObject("roSGNode", "Rectangle")
    card.color = "0x0B0E17F5"
    card.width = 840
    card.height = 360
    card.translation = "[540,360]"
    g.appendChild(card)

    cardAccent = CreateObject("roSGNode", "Rectangle")
    cardAccent.color = "0xD42028FF"
    cardAccent.width = 840
    cardAccent.height = 4
    cardAccent.translation = "[540,356]"
    g.appendChild(cardAccent)

    big = CreateObject("roSGNode", "Label")
    big.width = 720
    big.height = 44
    big.translation = "[600,434]"
    big.horizAlign = "center"
    big.vertAlign = "center"
    big.font = "font:MediumBoldSystemFont"
    big.color = "0xFFFFFFFF"
    big.text = "RESUME?"
    g.appendChild(big)

    sub2 = CreateObject("roSGNode", "Label")
    sub2.width = 720
    sub2.height = 40
    sub2.translation = "[600,482]"
    sub2.horizAlign = "center"
    sub2.vertAlign = "center"
    sub2.font = "font:SmallSystemFont"
    sub2.color = "0x9CA3AFFF"
    sub2.wrap = true
    sub2.maxLines = 1
    t = ProfilesStr(m.saveMeta, "title", "")
    if t = "" then t = "This title"
    sub2.text = t + "  •  " + ProfilesFormatTime(posSec)
    g.appendChild(sub2)

    content = CreateObject("roSGNode", "ContentNode")
    nd = content.createChild("ContentNode")
    nd.title = "Resume from " + ProfilesFormatTime(posSec)
    nd = content.createChild("ContentNode")
    nd.title = "Restart from beginning"
    list = CreateObject("roSGNode", "LabelList")
    list.content = content
    list.itemSize = "[640,56]"
    list.numRows = 2
    list.translation = "[640,534]"
    list.focusBitmapUri = "pkg:/images/btn_focus.png"
    list.focusFootprintBitmapUri = "pkg:/images/btn_footprint.png"
    list.color = "0x9CA3AFFF"
    list.focusedColor = "0xFFFFFFFF"
    list.observeField("itemSelected", "OnResumePicked")
    g.appendChild(list)

    m.resumePrompt = g
    m.resumeList = list
    m.promptOpen = true
    m.top.appendChild(g)
    list.setFocus(true)
    ? "RESUME prompt pos=" + posSec.ToStr()
end sub

sub HideResumePrompt()
    if m.resumePrompt <> invalid then
        kids = m.top.getChildren(-1, 0)
        for each k in kids
            if k.isSameNode(m.resumePrompt) then
                m.top.removeChild(m.resumePrompt)
                exit for
            end if
        end for
    end if
    m.resumePrompt = invalid
    m.resumeList = invalid
    m.promptOpen = false
end sub

sub OnResumePicked(msg as Object)
    if m.resumeList = invalid then return
    idx = m.resumeList.itemSelected
    if idx = invalid then return
    if idx = 1 then
        st = ProfilesLoad()
        ProfilesClearResume(st, m.profileId, m.saveMeta)
        m.existingResume = invalid
        if m.video <> invalid then m.video.seek = 0
        ? "RESUME restart chosen"
    else
        if m.video <> invalid and m.resumePos > 0 then
            m.video.seek = m.resumePos
        end if
        ? "RESUME resume chosen pos=" + m.resumePos.ToStr()
    end if
    HideResumePrompt()
    if m.video <> invalid then
        m.video.setFocus(true)
    else
        m.top.setFocus(true)
    end if
end sub

sub OnVideoPosition(msg as Object)
    if m.stopped then return
    if m.promptOpen then return
    if m.video = invalid then return
    if m.saveMeta = invalid or m.profileId = "" then return
    if m.saveMeta.tmdbId = "" then return
    curPos = msg.getData()
    if curPos = invalid then return
    p = Int(curPos)
    if p < 10 then return
    ' Fresh clock per read (audit finding): m.clock was created once in init,
    ' so AsSeconds() returned its creation time forever and the 15s throttle
    ' only ever let the FIRST position save through — mid-movie crash/resume
    ' positions were lost.
    now = CreateObject("roDateTime").AsSeconds()
    ' Throttle registry writes during playback (pause/stop/finish save now).
    if now - m.lastSaveSec < 15 then return
    m.lastSaveSec = now
    WriteResumePoint(p, ReadDurationSec())
end sub

function ReadDurationSec() as Integer
    if m.video = invalid then return 0
    dur = m.video.duration
    if dur = invalid then return 0
    return Int(dur)
end function

sub WriteResumePoint(p as Integer, d as Integer)
    if m.saveMeta = invalid or m.profileId = "" then return
    if m.saveMeta.tmdbId = "" then return
    if d > 0 and p / d > 0.95 then
        st = ProfilesLoad()
        ProfilesClearResume(st, m.profileId, m.saveMeta)
        m.resumeCleared = true
        return
    end if
    st2 = ProfilesLoad()
    ProfilesPutResume(st2, m.profileId, m.saveMeta, p, d)
end sub

' Immediate (unthrottled) save used on pause and on exit.
sub SavePlaybackPosition()
    if m.promptOpen then return
    if m.video = invalid then return
    if m.saveMeta = invalid or m.profileId = "" then return
    if m.saveMeta.tmdbId = "" then return
    curPos = m.video.position
    if curPos = invalid then return
    p = Int(curPos)
    if p < 10 then return
    m.lastSaveSec = CreateObject("roDateTime").AsSeconds()
    WriteResumePoint(p, ReadDurationSec())
end sub
' Read-only ABR audit: logs the actual rendition the firmware picks
' (width/height/bitrate/HDR). Proves whether a "1080p" URL served
' SDR 1920x1080 or the 3840x2076 PQ variant -- no playback change.
sub OnStreamingSegment(evt as Object)
    if m.stopped then return
    seg = evt.getData()
    if seg = invalid then return
    w = ""
    h = ""
    br = ""
    hdr = ""
    if seg.width <> invalid then w = seg.width.ToStr()
    if seg.height <> invalid then h = seg.height.ToStr()
    if seg.segBitrateBps <> invalid then br = seg.segBitrateBps.ToStr()
    if seg.hdrModeStr <> invalid then hdr = seg.hdrModeStr
    ? "SEGMENT " + w + "x" + h + " bitrate=" + br + " hdr=" + hdr
end sub

' ------------------------------------------------------------------
' TV episode auto-advance ("Next up")
' ------------------------------------------------------------------

sub ShowNextUp()
    if m.nextUpGroup <> invalid then return
    g = CreateObject("roSGNode", "Rectangle")
    g.color = "0x000000E6"
    g.width = 1920
    g.height = 1080
    g.translation = "[0,0]"

    card = CreateObject("roSGNode", "Rectangle")
    card.color = "0x0B0E17F5"
    card.width = 840
    card.height = 360
    card.translation = "[540,360]"
    g.appendChild(card)

    cardAccent = CreateObject("roSGNode", "Rectangle")
    cardAccent.color = "0xD42028FF"
    cardAccent.width = 840
    cardAccent.height = 4
    cardAccent.translation = "[540,356]"
    g.appendChild(cardAccent)

    big = CreateObject("roSGNode", "Label")
    big.width = 720
    big.height = 44
    big.translation = "[600,434]"
    big.horizAlign = "center"
    big.vertAlign = "center"
    big.font = "font:MediumBoldSystemFont"
    big.color = "0xFFFFFFFF"
    big.text = "NEXT UP"
    g.appendChild(big)

    sub2 = CreateObject("roSGNode", "Label")
    sub2.width = 720
    sub2.height = 40
    sub2.translation = "[600,482]"
    sub2.horizAlign = "center"
    sub2.vertAlign = "center"
    sub2.font = "font:SmallSystemFont"
    sub2.color = "0x9CA3AFFF"
    sub2.wrap = true
    sub2.maxLines = 1
    sub2.text = "Checking next episode..."
    g.appendChild(sub2)
    m.nextUpSub = sub2

    content = CreateObject("roSGNode", "ContentNode")
    nd = content.createChild("ContentNode")
    nd.title = "Play next"
    nd = content.createChild("ContentNode")
    nd.title = "Close"
    list = CreateObject("roSGNode", "LabelList")
    list.content = content
    list.itemSize = "[640,56]"
    list.numRows = 2
    list.translation = "[640,534]"
    list.focusBitmapUri = "pkg:/images/btn_focus.png"
    list.focusFootprintBitmapUri = "pkg:/images/btn_footprint.png"
    list.color = "0x9CA3AFFF"
    list.focusedColor = "0xFFFFFFFF"
    list.observeField("itemSelected", "OnNextUpPicked")
    g.appendChild(list)

    m.nextUpGroup = g
    m.nextUpList = list
    m.top.appendChild(g)
    list.setFocus(true)
    FetchNextUpInfo()
    NextUpStartCountdown()
end sub

' 10-second auto-play countdown: when the episode ends, the prompt waits 10s
' then plays the next one on its own (Netflix-style). Any OK pick still
' works; the countdown stops when the overlay closes. If the next-episode
' info never resolved, the countdown leaves the prompt up (manual choice).
sub NextUpStartCountdown()
    NextUpStopTimer()
    timer = CreateObject("roSGNode", "Timer")
    if timer = invalid then return
    timer.duration = 1.0
    timer.repeat = true
    timer.observeField("fire", "OnNextUpTick")
    m.nextUpTimer = timer
    m.nextUpCount = 10
    m.top.appendChild(timer)
    timer.control = "start"
    ' Paint the starting value right away: without this the first visible
    ' number is 9 (the 1s tick fires before the user looks).
    if m.nextUpEpLabel <> "" then
        UpdateNextUpSub(m.nextUpEpLabel + "  -  playing in 10s")
    end if
end sub

' Stop the countdown AND take the node out of the tree. Stopping alone left
' a dead Timer parented to the scene, so every episode end leaked one.
sub NextUpStopTimer()
    if m.nextUpTimer = invalid then return
    m.nextUpTimer.control = "stop"
    kids = m.top.getChildren(-1, 0)
    for each k in kids
        if k.isSameNode(m.nextUpTimer) then
            m.top.removeChild(k)
            exit for
        end if
    end for
    m.nextUpTimer = invalid
end sub

sub OnNextUpTick()
    if m.nextUpGroup = invalid then return
    m.nextUpCount = m.nextUpCount - 1
    if m.nextUpCount <= 0 then
        if m.nextUpTimer <> invalid then m.nextUpTimer.control = "stop"
        if m.nextUpRec <> invalid and SafeStr(m.nextUpRec, "tmdbId", "") <> "" then
            ? "NEXTUP autoplay count=0"
            PlayNextEpisode(m.nextUpRec)
            return
        end if
        ' No resolved record: leave the prompt up for a manual pick. The node
        ' still has to go, or it keeps ticking against a dead overlay.
        NextUpStopTimer()
        return
    end if
    base = m.nextUpEpLabel
    if base = "" then base = "Next episode"
    UpdateNextUpSub(base + "  -  playing in " + m.nextUpCount.ToStr() + "s")
end sub

sub HideNextUp()
    if m.nextUpGroup <> invalid then
        kids = m.top.getChildren(-1, 0)
        for each k in kids
            if k.isSameNode(m.nextUpGroup) then
                m.top.removeChild(m.nextUpGroup)
                exit for
            end if
        end for
    end if
    m.nextUpGroup = invalid
    m.nextUpList = invalid
    NextUpStopTimer()
    if m.nextUpTask <> invalid then
        m.nextUpTask.control = "stop"
        m.nextUpTask = invalid
    end if
end sub

' Fetch the current season's episode list to decide same-season vs season
' boundary. Never auto-cross a season without prompting (the overlay always
' asks; if it is a boundary we label the option as the next season).
sub FetchNextUpInfo()
    if m.nextUpTask <> invalid then return
    if m.saveMeta = invalid then return
    tmdbId = SafeStr(m.saveMeta, "tmdbId", "")
    if tmdbId = "" then return
    s = ProfilesInt(m.saveMeta, "season", 1)
    if s < 1 then s = 1
    url = TmdbTvEpisodesUrl(m.cfg, tmdbId, s)
    task = CreateObject("roSGNode", "ApiTask")
    task.url = url
    task.headers = TmdbHeaders(m.cfg.tmdbKey)
    task.observeField("raw", "OnNextUpInfo")
    m.nextUpTask = task
    task.control = "run"
end sub

sub OnNextUpInfo()
    task = m.nextUpTask
    m.nextUpTask = invalid
    curSeason = ProfilesInt(m.saveMeta, "season", 1)
    if curSeason < 1 then curSeason = 1
    curEp = ProfilesInt(m.saveMeta, "episode", 0)
    nextEp = curEp + 1
    if nextEp < 1 then nextEp = 1
    total = 0
    if task <> invalid and task.raw <> "" and task.raw <> invalid then
        data = JsonParseSafe(task.raw)
        if data <> invalid then
            eps = SafeGet(data, "episodes", [])
            if type(eps) = "roArray" then
                total = eps.count()
            end if
        end if
    end if
    if total > 0 and nextEp > total then
        ' Season boundary: prompt explicitly rather than silently crossing.
        m.nextUpRec = {
            tmdbId: SafeStr(m.saveMeta, "tmdbId", ""),
            mediaType: "tv",
            season: (curSeason + 1).ToStr(),
            episode: "1",
            title: SafeStr(m.saveMeta, "title", ""),
            poster: SafeStr(m.saveMeta, "poster", "")
        }
        UpdateNextUpSub("Next season - S" + Pad2Num(curSeason + 1) + "E1")
        m.nextUpEpLabel = "Next season - S" + Pad2Num(curSeason + 1) + "E1"
    else
        m.nextUpRec = {
            tmdbId: SafeStr(m.saveMeta, "tmdbId", ""),
            mediaType: "tv",
            season: curSeason.ToStr(),
            episode: nextEp.ToStr(),
            title: SafeStr(m.saveMeta, "title", ""),
            poster: SafeStr(m.saveMeta, "poster", "")
        }
        UpdateNextUpSub("S" + Pad2Num(curSeason) + "E" + Pad2Num(nextEp))
        m.nextUpEpLabel = "S" + Pad2Num(curSeason) + "E" + Pad2Num(nextEp)
    end if
end sub

sub UpdateNextUpSub(text as String)
    if m.nextUpSub <> invalid then
        m.nextUpSub.text = text
    end if
end sub

sub OnNextUpPicked()
    if m.nextUpList = invalid then return
    idx = m.nextUpList.itemSelected
    if idx = 0 then
        PlayNextEpisode(m.nextUpRec)
    else
        ClosePlayback()
    end if
end sub

sub PlayNextEpisode(rec as Object)
    HideNextUp()
    if m.stopped then return
    if rec = invalid or SafeStr(rec, "tmdbId", "") = "" then
        ClosePlayback()
        return
    end if
    RemoveVideo()
    m.top.resumeRec = rec
    m.saveMeta = ProfilesMetaForRec(rec, {})
    m.profileId = ProfilesGetActiveId(m.profiles)
    m.existingResume = invalid
    m.resumeCleared = false
    m.pendingRec = rec
    ResolveEpisode(rec)
end sub

sub RemoveVideo()
    if m.video = invalid then return
    m.video.control = "stop"
    kids = m.top.getChildren(-1, 0)
    for each k in kids
        if k.isSameNode(m.video) then
            m.top.removeChild(m.video)
            exit for
        end if
    end for
    m.video = invalid
end sub

function Pad2Num(n as Integer) as String
    if n < 10 then
        return "0" + n.ToStr()
    end if
    return n.ToStr()
end function

sub OnVideoState(evt)
    ' A state event can arrive after ClosePlayback has begun tearing the scene
    ' down (finished -> paused/error re-fire). Re-entering on a half-destroyed
    ' scene (or re-closing) is a render-thread crash that kills the channel to
    ' the OS home screen.
    if m.stopped then return
    state = evt.getData()
    if state = invalid then state = ""
    if type(state) <> "roString" and type(state) <> "String" then state = state.ToStr()
    info = ""
    if m.video <> invalid then
        ec = m.video.errorCode
        em = m.video.errorMsg
        if ec <> invalid then
            info = info + " code=" + ec.ToStr()
        end if
        if em <> invalid and em <> "" then
            info = info + " msg=" + em
        end if
    end if
    ? "VIDEO state=" + state + info
    if state = "finished" then
        ' Clear the finished episode's/movie's resume point either way.
        st = ProfilesLoad()
        ProfilesClearResume(st, m.profileId, m.saveMeta)
        m.resumeCleared = true
        ' TV auto-advance: offer "Next up" (same season) before closing.
        if SafeStr(m.saveMeta, "mediaType", "") = "tv" and SafeStr(m.saveMeta, "tmdbId", "") <> "" then
            ShowNextUp()
            return
        end if
        ClosePlayback()
    else if state = "paused" then
        SavePlaybackPosition()
    else if state = "error" then
        RemoveVideo()
        ShowError("Sorry, this stream could not be played. Try Retry, or press BACK.")
    end if
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then
        return false
    end if
    if key = "back" then
        ' Next-up overlay: Back declines auto-advance and closes.
        if m.nextUpGroup <> invalid then
            HideNextUp()
            ClosePlayback()
            return true
        end if
        ' Dismissing the resume prompt keeps playing from the live position
        ' and keeps the stored point (nothing is cleared).
        if m.resumePrompt <> invalid then
            HideResumePrompt()
            if m.video <> invalid then
                m.video.setFocus(true)
            else
                m.top.setFocus(true)
            end if
            return true
        end if
        ClosePlayback()
        return true
    end if
    return false
end function

sub ClosePlayback()
    ' Idempotent: Back and a "finished" state event can both call this. The
    ' second call must not touch nodes that HomeScene/EpisodeScene already
    ' tore down, or the render thread dies and the channel exits to the OS home.
    if m.closed then return
    m.closed = true
    m.stopped = true
    if not m.resumeCleared then
        SavePlaybackPosition()
    end if
    if m.video <> invalid then
        m.video.control = "stop"
    end if
    ' Stop any in-flight TV resolve task so its observer cannot fire on a
    ' scene that is about to be removed.
    if m.pendingTask <> invalid then
        m.pendingTask.control = "stop"
        m.pendingTask = invalid
    end if
    if m.femTask <> invalid then
        m.femTask.control = "stop"
        m.femTask = invalid
    end if
    if m.vixTask <> invalid then
        m.vixTask.control = "stop"
        m.vixTask = invalid
    end if
    if m.nextUpTask <> invalid then
        m.nextUpTask.control = "stop"
        m.nextUpTask = invalid
    end if
    PersistDrain()
    m.top.done = true
end sub
