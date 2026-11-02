' LiveTvScene: genre-based live TV — genre rail (left), channel guide
' (middle), preview + info (right), fullscreen on OK.
'
' DATA-LAYER CONTRACT (implemented by sibling: components/LiveTv.brs +
' components/CineVid.brs + components/tasks/LiveTvTask.xml/.brs):
'   Task node "LiveTvTask", mode "all"/"channels"/"epg" + field "source"
'   ("free" default | "premium"). Observe "status" (alwaysNotify):
'   200 = ok -> read "channels" (array) + "epg" (assocarray; {} for premium).
'   11/12/21/22/98 = failure -> read "errorDetail" (98 = unexpected exception
'   in the task; its errorDetail names the run stage + message). Task
'   self-terminates.
'   channels[] entries: {id,title,thumbnail,url,epgId,genre,chNo(int 1..N,
'     sequential),description,source("free" implicit | "cinevid")}.
'   Premium (cinevid) records carry url "" BY DESIGN: every tune resolves a
'   FRESH stream token via task mode "resolve" (observe "resolveStatus":
'   200 ok -> "resolvedUrl", 11 failed) — tokens are short-lived, so replays
'   (fullscreen enter/exit) re-resolve instead of caching.
'   epg: {epgId:{programs:[{title,start,stop,desc}], now:{title,start,stop},
'     next:[{title,start,stop} x up to 2]}}. Times are epoch seconds.
'   NOTE: "stop" is a BrightScript reserved word: always use prog["stop"],
'   never the dot form.
'
' BROWSE MODEL (2026-09-23 redesign): the left rail lists canonical genres
' (All Channels, Premium, Sports, ...) — free channels are bucketed from
' Samsung's group strings via LiveTvGenreFromGroup(), premium is its own
' genre per user request. The middle list shows the selected genre's
' channels, sequentially numbered CH 1..N, with now/next info for free
' channels. Zones: genres <-> channels <-> fullscreen. Focus surfing tunes
' the preview debounced (surfTimer, 0.4s); OK enters fullscreen.
'
' FULLSCREEN (v6, bare Video in this group): v1 resized a playing node (the
' plane never moved), v2 created a bare Video nested in the Live TV group,
' v3 pre-declared a bare Video invisible in HomeScene.xml, v4 appended a bare
' Video to the scene root (keys orphaned past onKeyEvent), v5 tried an
' FsVideo Video-SUBCLASS component (no picture — the only video pattern in
' this app with no working precedent). What DOES render: every Video
' declared inside a COMPONENT (the splash full-screen every boot; this
' scene's preview at its rect), and bare runtime Videos parented to a Group
' (PlaybackScene.StartVideo plays movies exactly that way). So v6 is a bare
' Video again like v2/v4, but parented to m.top (this LiveTvScene group, NOT
' the scene root): a FRESH instance at every fullscreen enter, preview node
' fully hidden, destroyed at exit. The fsDim rectangle stays as the fallback
' diagnostic behind the player: dark screen + no picture = compositor issue;
' no change at all = the picked handler never fired.
'
' Layout (1920x1080 fhd, dark + red accent, matches HomeScene):
'   header 0..150 | genres x48 w420 (list y224, 12x56 rows) |
'   channels x490 w700 (list y224, 12x60 rows) |
'   preview video [1210,170] 662x372 + info block below it.

sub init()
    m.liveTvChannels = []
    m.liveTvFreeChannels = []
    m.liveTvPremiumChannels = []
    m.liveTvPremiumTask = invalid
    m.liveTvPremiumTicks = 0
    m.liveTvGenre = "all"
    m.liveTvGenreIds = []
    m.liveTvEpg = {}
    m.liveTvIndex = 0
    m.liveTvTunedIdx = -1
      m.liveTvZone = "channels"
      m.liveTvZoneBeforeFs = "channels"
      m.liveTvZoneBeforeGrid = "channels"
    m.liveTvSyncing = false
    m.liveTvTask = invalid
    m.liveTvClosed = false
    m.liveTvTuneFails = 0
    ' Extra tune-watchdog windows granted to a stream that is buffering rather
    ' than failing. Reset on every playback start, so it can never accumulate
    ' across channels. See LiveTvOnTuneTimeout.
    m.liveTvWatchdogRearms = 0
    ' How many 20s tune-watchdog windows a single premium resolve has already
    ' deferred. Bounded (2 = 40s > the 25s resolve fetch) so a resolve that
    ' never posts resolveStatus still ends in the normal retry instead of a
    ' permanent black screen. See LiveTvOnTuneTimeout.
    m.liveTvResolveDefers = 0
    m.liveTvResolveReason = ""
    m.liveTvPhase = "channels"
    m.liveTvSurfIdx = -1

    m.liveTvGenreList = m.top.findNode("genreList")
    m.liveTvChannelList = m.top.findNode("channelList")
    m.liveTvBrowseGroup = m.top.findNode("browseGroup")
    ' LIVE GRID: view state + container. The container is created empty and
    ' hidden in init; the rail's "Live Grid" entry fills it on demand.
    m.liveTvGridState = {}
    m.liveTvGridRoot = invalid
    m.liveTvGridOpen = false
    m.liveTvPreview = m.top.findNode("previewVideo")
    m.liveTvVideo = m.liveTvPreview
    m.liveTvFsVideo = m.top.findNode("fsVideo")
    m.liveTvFsAttached = false
    m.liveTvIgnoreNextOk = false
    m.liveTvIgnoreNextGridOk = false
    m.liveTvBrowse = m.top.findNode("browseGroup")
    ' The grid is built from plain Rectangles/Labels and has no focusable
    ' child, so the ONLY way its keys can arrive is for this scene group
    ' itself to take focus. A Group is NOT focusable by default, which is why
    ' LiveTvGridOpenView's m.top.setFocus(true) silently did nothing and the
    ' open guide ate no keys at all: UP/DOWN went to the rail behind it and
    ' the grid looked frozen. focusable has to be set in init, before the
    ' first setFocus, or the flag is still false when the call is made.
    m.top.focusable = true
    m.liveTvFsDim = m.top.findNode("fsDim")
    m.liveTvInfoName = m.top.findNode("infoName")
    m.liveTvInfoNowMeta = m.top.findNode("infoNowMeta")
    m.liveTvInfoNow = m.top.findNode("infoNow")
    m.liveTvInfoTrack = m.top.findNode("infoTrack")
    m.liveTvInfoFill = m.top.findNode("infoFill")
    m.liveTvInfoNextMeta = m.top.findNode("infoNextMeta")
    m.liveTvInfoNext = m.top.findNode("infoNext")
    m.liveTvInfoDesc = m.top.findNode("infoDesc")
    m.liveTvError = m.top.findNode("errorLabel")
    m.liveTvErrorBg = m.top.findNode("errorBg")
    m.liveTvErrorAccent = m.top.findNode("errorAccent")
    m.liveTvGuideHeader = m.top.findNode("guideHeader")
    m.liveTvStatus = m.top.findNode("statusLabel")
    m.liveTvClockLabel = m.top.findNode("clockLabel")
    m.liveTvClockTimer = m.top.findNode("clockTimer")
    m.liveTvTuneTimer = m.top.findNode("tuneTimer")
    m.liveTvLoadTimer = m.top.findNode("loadTimer")
    m.liveTvSurfTimer = m.top.findNode("surfTimer")

    ' FEATURE 1: cable-style fullscreen info banner (stock nodes, XML-declared).
    m.liveTvFsBanner = m.top.findNode("fsBanner")
    m.liveTvFsBannerChan = m.top.findNode("fsBannerChan")
    m.liveTvFsBannerClock = m.top.findNode("fsBannerClock")
    m.liveTvFsBannerNowMeta = m.top.findNode("fsBannerNowMeta")
    m.liveTvFsBannerNow = m.top.findNode("fsBannerNow")
    m.liveTvFsBannerNextMeta = m.top.findNode("fsBannerNextMeta")
    m.liveTvFsBannerNext = m.top.findNode("fsBannerNext")
    m.liveTvFsBannerDesc = m.top.findNode("fsBannerDesc")
    m.liveTvBannerTimer = m.top.findNode("bannerTimer")

    ' FEATURE 2: Sudo Movies virtual channel (own genre + movie queue).
    m.liveTvSudoChannels = []
    m.liveTvSudoMovies = []
    m.liveTvSudoIdx = 0
    m.liveTvSudoSkips = 0
    m.liveTvSudoTask = invalid
    ' ARTIFICIAL LIVE: fixed epoch anchor (past) so the 2h movie slots form a
    ' deterministic schedule that NEVER resets between visits - joining at
    ' 8:35 PM lands you 35 minutes INTO the movie that "started" at 8:00,
    ' like a real cable channel. Slot = floor((now-anchor)/7200); the movie
    ' at that position plays with seek = offset.
    m.liveTvSudoAnchor = 1790000000
    m.liveTvSudoSeekTo = 0
    m.liveTvSudoJoinSeeking = false
    m.liveTvSudoSlotStart = 0
    m.liveTvSudoLineupTask = invalid

    ' Per-tune premium resolve task (distinct from the lineup task: one
    ' Task node cannot serve both).
    m.liveTvResolveTask = invalid

    if m.liveTvGenreList <> invalid then
        m.liveTvGenreList.observeField("itemSelected", "LiveTvOnGenrePicked")
    end if
    if m.liveTvChannelList <> invalid then
        m.liveTvChannelList.observeField("itemFocused", "LiveTvOnChannelFocused")
        m.liveTvChannelList.observeField("itemSelected", "LiveTvOnChannelPicked")
    end if
    if m.liveTvVideo <> invalid then
        m.liveTvVideo.observeField("state", "LiveTvOnVideoState")
    end if
    if m.liveTvClockTimer <> invalid then
        m.liveTvClockTimer.observeField("fire", "LiveTvOnClockTick")
        m.liveTvClockTimer.control = "start"
    end if
    if m.liveTvTuneTimer <> invalid then
        m.liveTvTuneTimer.observeField("fire", "LiveTvOnTuneTimeout")
    end if
    if m.liveTvLoadTimer <> invalid then
        m.liveTvLoadTimer.observeField("fire", "LiveTvOnLoadTimeout")
    end if
    if m.liveTvSurfTimer <> invalid then
        m.liveTvSurfTimer.observeField("fire", "LiveTvOnSurfSettled")
    end if
    if m.liveTvBannerTimer <> invalid then
        m.liveTvBannerTimer.observeField("fire", "LiveTvOnBannerTimeout")
    end if

    LiveTvUpdateClock()
    LiveTvLoadData()
    if m.liveTvChannelList <> invalid then
        m.liveTvChannelList.setFocus(true)
    end if
end sub

' ------------------------------------------------------------------
' Data loading (LiveTvTask contract, see file header)
' ------------------------------------------------------------------

sub LiveTvLoadData()
    ' Free lineup first: split-phase load (channels, then the guide merges
    ' in the background). Premium loads on demand the first time its genre
    ' is picked (LiveTvEnsurePremium).
    m.liveTvPhase = "channels"
    LiveTvSetStatus("Loading channels...")
    LiveTvStartTask("channels", "free")
end sub

' Kick off the premium (cinevid) lineup fetch if it is not loaded yet.
' Called from the genre rail; results land in LiveTvOnTaskStatus with
' phase "premium".
' Premium lineup used to run on the SHARED task, which meant a background
' premium load aborted an in-flight EPG fetch (the same class of bug the
' sudo lineup had). It now owns its task ref and loads in the BACKGROUND
' after the free lineup lands, because premium channels are merged into the
' genre buckets and cannot wait for the user to open the Premium tab.
sub LiveTvEnsurePremium()
    if m.liveTvPremiumChannels.count() > 0 then return
    if m.liveTvPremiumTask <> invalid then return
    LiveTvLoadPremiumData()
end sub

sub LiveTvLoadPremiumData()
    LiveTvStopPremiumLineupTask()
    task = CreateObject("roSGNode", "LiveTvTask")
    if task = invalid then return
    m.liveTvPremiumTask = task
    m.liveTvPremiumTicks = 0
    ? "LIVETV premium lineup fetch begin"
    task.observeField("status", "LiveTvOnPremiumLineupStatus")
    task.source = "premium"
    task.mode = "channels"
    task.control = "run"
end sub

sub LiveTvStopPremiumLineupTask()
    if m.liveTvPremiumTask <> invalid then
        m.liveTvPremiumTask.control = "stop"
        m.liveTvPremiumTask = invalid
    end if
end sub

' Watchdog. The premium lineup runs on its own background task, so it is not
' covered by the shared loadTimer: if the node never reports a terminal
' status (network stall, firmware drop), the ref would stay latched and
' LiveTvEnsurePremium would refuse to retry for the rest of the session -
' which presented as "Premium is broken" with no way back. Two 30s clock
' ticks is the same order as the shared 85s loadTimer.
sub LiveTvPremiumWatchdog()
    if m.liveTvPremiumTask = invalid then return
    m.liveTvPremiumTicks = m.liveTvPremiumTicks + 1
    if m.liveTvPremiumTicks < 2 then return
    ? "LIVETV premium lineup watchdog fired"
    LiveTvStopPremiumLineupTask()
    m.liveTvPremiumChannels = []
    if m.liveTvGenre = "premium" then
        LiveTvSetStatus("Premium timed out. Press BACK, then open Premium again to retry.")
    end if
end sub

' Identity-guarded exactly like the sudo lineup handler.
sub LiveTvOnPremiumLineupStatus(evt as Object)
    if m.liveTvClosed then return
    task = m.liveTvPremiumTask
    if task = invalid then return
    src = evt.getRoSGNode()
    if src = invalid then return
    if not src.isSameNode(task) then return
    st = task.status
    if st = invalid or st = 0 then return
    m.liveTvPremiumTask = invalid
    m.liveTvPremiumTicks = 0
    channels = task.getField("channels")
    detail = ""
    if task.hasField("errorDetail") then detail = task.getField("errorDetail")
    np = 0
    if type(channels) = "roArray" then np = channels.count()
    ? "LIVETV premium lineup done status=" + st.ToStr() + " n=" + np.ToStr()
    LiveTvOnPremiumStatus(st, channels, detail)
end sub

sub LiveTvStartTask(mode as String, source as String)
    LiveTvStopTask()
    task = CreateObject("roSGNode", "LiveTvTask")
    if task = invalid then
        LiveTvSetStatus("Live TV is not available in this build. Press BACK.")
        return
    end if
    if task.hasField("source") then
        task.source = source
    end if
    ' FEATURE 2: TMDB key path LiveTvScene -> LiveTvTask (sudo lineup fetch).
    ' Defaults to the bundled key when HomeScene passes nothing.
    if task.hasField("tmdbKey") then
        key = ""
        if m.top.tmdbKey <> invalid then key = m.top.tmdbKey
        if key = "" then key = AppConstants().tmdbDefaultKey
        task.tmdbKey = key
    end if
    m.liveTvTask = task
    task.observeField("status", "LiveTvOnTaskStatus")
    if m.liveTvLoadTimer <> invalid then m.liveTvLoadTimer.control = "start"
    task.mode = mode
    task.control = "run"
end sub

sub LiveTvStopTask()
    if m.liveTvLoadTimer <> invalid then m.liveTvLoadTimer.control = "stop"
    if m.liveTvTask <> invalid then
        m.liveTvTask.control = "stop"
        m.liveTvTask = invalid
    end if
end sub

sub LiveTvOnTaskStatus(evt as Object)
    if m.liveTvClosed then return
    if m.liveTvTask = invalid then return
    ' IDENTITY FROM THE EVENT, not the mutable ref: m.liveTvTask can be
    ' reassigned between a task's completion and this observer running,
    ' which silently dropped every EPG completion (guide never merged).
    task = evt.getRoSGNode()
    if task = invalid then return
    if not task.isSameNode(m.liveTvTask) then return
    st = task.status
    if st = invalid then return
    if st = 0 then return
    channels = task.getField("channels")
    epg = task.getField("epg")
    sudoMovies = task.getField("sudoMovies")
    detail = ""
    if task.hasField("errorDetail") then detail = task.getField("errorDetail")
    ' Stop the task node itself BEFORE clearing the ref: LiveTvStopTask acts
    ' on m.liveTvTask, so clearing first would orphan a running task.
    LiveTvStopTask()
    ' ROUTE ON THE TASK'S OWN MODE, not m.liveTvPhase: the independent sudo
    ' lineup task finishes on its own clock and used to reset the shared
    ' phase, which made a still-running stvg/epg completion mis-route into
    ' the base channel path and re-fetch the 2.9MB primary guide. The task
    ' node's mode/source is written by LiveTvStartTask before control="run",
    ' so it is always accurate; the identity check above guarantees this
    ' event came from m.liveTvTask.
    mode = task.getField("mode")
    if mode = invalid then mode = ""
    tsrc = ""
    if task.hasField("source") then
        s2 = task.getField("source")
        if s2 <> invalid then tsrc = s2
    end if
    if mode = "epg" then
        LiveTvOnEpgStatus(st, epg, detail)
        return
    end if
    if mode = "stvg" then
        LiveTvOnStvgStatus(st, epg, detail)
        return
    end if
    if mode = "channels" and tsrc = "premium" then
        LiveTvOnPremiumStatus(st, channels, detail)
        return
    end if
    if mode = "sudo" then
        LiveTvOnSudoStatus(st, channels, epg, sudoMovies, detail)
        return
    end if
    if st = 200 then
        LiveTvApplyData(channels, epg)
        LiveTvLoadEpgData()
        return
    end if
    ' Partial success: the task stores channels before the EPG fetch, so a
    ' guide failure (21/22) can still leave a usable channel lineup.
    if type(channels) = "roArray" and channels.count() > 0 then
        if type(epg) <> "roAssociativeArray" then epg = {}
        LiveTvApplyData(channels, epg)
        LiveTvLoadEpgData()
        return
    end if
    msg = "Live TV guide failed (code " + st.ToStr() + "). Press BACK and try again."
    if detail <> invalid and detail <> "" then msg = detail
    LiveTvSetStatus(msg)
    ' No fetch is in flight anymore: reset the phase so the genre-switch
    ' self-heals in LiveTvSelectGenre can retry instead of being blocked.
    m.liveTvPhase = "idle"
end sub

' Premium lineup arrival: store it, refresh the rail count, and if the
' user is sitting on the Premium genre render it now.
sub LiveTvOnPremiumStatus(st as Integer, channels as Object, detail as String)
    if st = 200 and type(channels) = "roArray" and channels.count() > 0 then
        m.liveTvPremiumChannels = channels
        LiveTvRenderGenres()
        ' Premium is merged into the genre buckets, so an open genre list has
        ' to be rebuilt now that the premium half exists. The grid keeps its
        ' own scroll position and refreshes on the next open instead.
        if m.liveTvGenre <> "premium" and m.liveTvGenre <> "grid" and m.liveTvGenre <> "" and m.liveTvChannels.count() > 0 then
            LiveTvShowGenreList()
            LiveTvSelectChannel(m.liveTvIndex, false)
        end if
        if m.liveTvGenre = "premium" then
            LiveTvShowGenreList()
            LiveTvSelectChannel(0, true)
            LiveTvSetStatus("Up/Down surf  •  OK fullscreen  •  Back exit")
        end if
        return
    end if
    if m.liveTvGenre = "premium" then
        msg = "Premium channels unavailable (code " + st.ToStr() + ")."
        if detail <> invalid and detail <> "" then msg = detail
        LiveTvSetStatus(msg)
    end if
end sub

sub LiveTvLoadEpgData()
    m.liveTvPhase = "epg"
    LiveTvSetStatus("Channels loaded - loading guide...")
    LiveTvStartTask("epg", "free")
end sub

' ------------------------------------------------------------------
' FEATURE 2: Sudo Movies virtual channel. Silent background load (the guide
' is already usable); results land in LiveTvOnSudoStatus with phase "sudo".
' ------------------------------------------------------------------

sub LiveTvLoadSudoData()
    ' OWN TASK REF: the sudo load must never kill or reassign the shared
    ' lineup/EPG task. The old shared-ref flow called LiveTvStartTask, whose
    ' LiveTvStopTask aborted the running EPG fetch mid-parse — and the EPG
    ' completion was then dropped by the m.liveTvTask reassign. The guide
    ' never merged (the exact "no guide info" bug).
    LiveTvStopSudoLineupTask()
    task = CreateObject("roSGNode", "LiveTvTask")
    if task = invalid then return
    if task.hasField("tmdbKey") then
        key = ""
        if m.top.tmdbKey <> invalid then key = m.top.tmdbKey
        if key = "" then key = AppConstants().tmdbDefaultKey
        task.tmdbKey = key
    end if
    m.liveTvSudoLineupTask = task
    task.observeField("status", "LiveTvOnSudoLineupStatus")
    if task.hasField("sudoAnchor") then task.sudoAnchor = m.liveTvSudoAnchor
    task.mode = "sudo"
    task.control = "run"
end sub

sub LiveTvStopSudoLineupTask()
    if m.liveTvSudoLineupTask <> invalid then
        m.liveTvSudoLineupTask.control = "stop"
        m.liveTvSudoLineupTask = invalid
    end if
end sub

' Sudo lineup completion: identity-guarded via the event source (the same
' rule as the shared handler). Routes into LiveTvOnSudoStatus untouched.
sub LiveTvOnSudoLineupStatus(evt as Object)
    if m.liveTvClosed then return
    task = m.liveTvSudoLineupTask
    if task = invalid then return
    src = evt.getRoSGNode()
    if src = invalid then return
    if not src.isSameNode(task) then return
    st = task.status
    if st = invalid or st = 0 then return
    m.liveTvSudoLineupTask = invalid
    channels = task.getField("channels")
    epg = task.getField("epg")
    sudoMovies = task.getField("sudoMovies")
    detail = ""
    if task.hasField("errorDetail") then detail = task.getField("errorDetail")
    nmv = 0
    if type(sudoMovies) = "roArray" then nmv = sudoMovies.count()
    ? "LIVETV sudo lineup done status=" + st.ToStr() + " movies=" + nmv.ToStr()
    LiveTvOnSudoStatus(st, channels, epg, sudoMovies, detail)
end sub

' Sudo lineup arrival: store the virtual channel + movie queue, merge the
' fabricated guide into the live EPG, refresh the rail count. If the user is
' sitting on the Sudo Movies genre, render it now. Failures stay silent
' unless that genre is on screen (free/premium flows untouched).
sub LiveTvOnSudoStatus(st as Integer, channels as Object, epg as Object, sudoMovies as Object, detail as String)
    if st = 200 and type(channels) = "roArray" and channels.count() > 0 then
        m.liveTvSudoChannels = channels
        if type(sudoMovies) = "roArray" then m.liveTvSudoMovies = sudoMovies
        if type(epg) = "roAssociativeArray" then
            for each k in epg
                m.liveTvEpg[k] = epg[k]
            end for
        end if
        if m.liveTvSudoIdx < 0 or m.liveTvSudoIdx >= m.liveTvSudoMovies.count() then m.liveTvSudoIdx = 0
        LiveTvEnsureSudoEpg()
        LiveTvRenderGenres()
        LiveTvGridRefreshData()
        if m.liveTvGenre = "sudo" then
            LiveTvShowGenreList()
            LiveTvSelectChannel(0, true)
            LiveTvSetStatus("Up/Down surf - OK fullscreen - Back exit")
        end if
        ' Do NOT clear the phase while a shared run is in flight: this task
        ' finishes on its own clock, and stomping the phase would break the
        ' phase guards the epg/stvg run depends on.
        if m.liveTvTask = invalid then m.liveTvPhase = "idle"
        return
    end if
    if m.liveTvGenre = "sudo" then
        msg = "Sudo Movies unavailable right now."
        if detail <> invalid and detail <> "" then msg = detail
        LiveTvSetStatus(msg)
    end if
    if m.liveTvTask = invalid then m.liveTvPhase = "idle"
end sub

sub LiveTvOnEpgStatus(st as Integer, epg as Object, detail as String)
    if st = 200 and type(epg) = "roAssociativeArray" then
        LiveTvApplyEpg(epg)
        ' FEATURE 2: guide merged - now load the Sudo Movies virtual channel
        ' in the background (silent: never clobbers the ready status line).
        LiveTvLoadSudoData()
        return
    end if
    msg = "Guide data unavailable - channels only. Up/Down surf still works."
    if detail <> invalid and detail <> "" then msg = detail
    LiveTvSetStatus(msg)
    ' FEATURE 2: the sudo lineup loads independently of the XMLTV guide.
    LiveTvLoadSudoData()
    ' Fallback guide source: when the primary XMLTV guide failed, try the
    ' Streaming TV Guides pages (name-keyed merge) before settling for
    ' channels-only. The shared task ref is free here (the failed run
    ' stopped); the completion routes back through phase "stvg".
    m.liveTvPhase = "stvg"
    LiveTvStartTask("stvg", "free")
end sub

' Streaming TV Guides fallback arrival: merge the name-keyed EPG into the
' live EPG and re-render under the sync guard (mirror of LiveTvApplyEpg,
' but MERGING - never replacing the primary XMLTV data already present).
sub LiveTvOnStvgStatus(st as Integer, epg as Object, detail as String)
    if st = 200 and type(epg) = "roAssociativeArray" and epg.count() > 0 then
        merged = 0
        for each k in epg
            if not m.liveTvEpg.DoesExist(k) then merged = merged + 1
            m.liveTvEpg[k] = epg[k]
        end for
        ? "LIVETV stvg merged new=" + merged.ToStr() + " total=" + m.liveTvEpg.count().ToStr()
        if m.liveTvChannels.count() > 0 then
            idx = m.liveTvIndex
            m.liveTvSyncing = true
            LiveTvRenderChannels()
            if m.liveTvChannelList <> invalid then m.liveTvChannelList.jumpToItem = idx
            m.liveTvSyncing = false
            LiveTvUpdateInfo()
            LiveTvGridRefreshData()
            LiveTvSetStatus("Up/Down surf  •  OK fullscreen  •  Back exit")
        end if
    end if
    m.liveTvPhase = "idle"
end sub

' Merge a background guide run into the already-rendered channel rows
' without yanking focus: re-render under the sync guard, restore the list
' position, then refresh the info block.
sub LiveTvApplyEpg(epg as Object)
    if type(epg) <> "roAssociativeArray" then return
    if m.liveTvChannels.count() = 0 then return
    m.liveTvEpg = epg
    idx = m.liveTvIndex
    m.liveTvSyncing = true
    LiveTvRenderChannels()
    if m.liveTvChannelList <> invalid then m.liveTvChannelList.jumpToItem = idx
    m.liveTvSyncing = false
    LiveTvUpdateInfo()
    LiveTvGridRefreshData()
    LiveTvSetStatus("Up/Down surf  •  OK fullscreen  •  Back exit")
end sub

sub LiveTvOnLoadTimeout()
    if m.liveTvTask = invalid then return
    task = m.liveTvTask
    LiveTvStopTask()
    if m.liveTvPhase = "epg" and m.liveTvChannels.count() > 0 then
        ' Channels are already showing; only the background guide died.
        LiveTvSetStatus("Guide data timed out - channels only. Up/Down surf still works.")
        ' FEATURE 2: the sudo lineup does not depend on the XMLTV guide.
        LiveTvLoadSudoData()
        return
    end if
    if m.liveTvPhase = "premium" then
        LiveTvSetStatus("Premium channels timed out - check your network connection. Press BACK and retry.")
        m.liveTvPhase = "idle"
        return
    end if
    if m.liveTvChannels.count() > 0 then return
    ' The task stores channels before the guide fetch, so a timed-out run
    ' can still hand over a usable lineup: apply it channels-only instead of
    ' showing a silent empty grid.
    ch = invalid
    if task.hasField("channels") then ch = task.getField("channels")
    if type(ch) = "roArray" and ch.count() > 0 then
        LiveTvApplyData(ch, {})
        LiveTvSetStatus("Guide data timed out - channels only. Up/Down surf still works.")
        m.liveTvPhase = "idle"
        return
    end if
    LiveTvSetStatus("Live TV timed out - check your network connection. Press BACK and try again.")
    m.liveTvPhase = "idle"
end sub

' Free lineup arrival: store, render the rail + current genre's channel
' list, tune the first channel.
sub LiveTvApplyData(channels as Object, epg as Object)
    if type(channels) <> "roArray" then channels = []
    if type(epg) <> "roAssociativeArray" then epg = {}
    m.liveTvFreeChannels = channels
    m.liveTvEpg = epg
    if channels.count() = 0 then
        LiveTvSetStatus("No live channels found. Press BACK and try again later.")
        return
    end if
    LiveTvRenderGenres()
    LiveTvShowGenreList()
    LiveTvSelectChannel(0, true)
    ' Premium (cinevid) is switched OFF for now: the index is unreachable from
    ' the device, so there is no point burning a background task on it. The
    ' plumbing above/below is left intact; re-enable by restoring this call
    ' and re-adding the "premium" entry in LiveTvCanonicalGenres().
    ' LiveTvEnsurePremium()
end sub

' ------------------------------------------------------------------
' LIVE GRID (cable-style time grid)
' ------------------------------------------------------------------
' The rail's first entry is a view, not a genre: it swaps the browse
' panels for the full-width time grid in LiveTvGrid.brs. The grid is drawn
' from plain Rectangles/Labels with no focusable child of its own, so the
' scene group itself takes focus (see init's m.top.focusable) and the scene
' keeps key ownership through its own onKeyEvent while the grid is up.
' ------------------------------------------------------------------

function LiveTvRailDefs() as Object
    defs = [{ id: "grid", label: "Live Grid" }]
    for each d in LiveTvCanonicalGenres()
        defs.Push(d)
    end for
    return defs
end function

' Local copy of the task's error-text helper, for ONE reason: this component
' does not include components/tasks/LiveTvTask.brs, so LiveTvTaskErrorText()
' is not in scope here. Roku reports an unknown function as a RUNTIME error,
' not a compile error, so calling it from inside a catch throws a second error
' from the handler - which is exactly the frozen-screen case the catch exists
' to prevent. The grid catch below must never be able to throw.
function LiveTvGridErrorText(e as Dynamic) as String
    detail = "grid build error"
    if e <> invalid then
        msg = invalid
        if type(e) = "roAssociativeArray" and e.DoesExist("Message") then
            msg = e["Message"]
        end if
        if msg <> invalid and (type(msg) = "String" or type(msg) = "roString") and msg <> "" then
            detail = detail + ": " + msg
        end if
    end if
    return detail
end function

' openedBySelect = true when the grid was opened by selecting the "grid" rail
' entry (the OK that opened it can still arrive as the grid's own OK), false
' when it was opened from the INFO shortcut (a different key, so nothing
' needs swallowing - arming the guard there ate the user's FIRST real OK).
sub LiveTvGridOpenView(openedBySelect as Boolean)
    ' A grid with no channels is an empty screen with a hint strip and no way
    ' out except BACK - which is indistinguishable from a freeze. It happens
    ' exactly when the lineup is still loading or a fetch failed, so refuse to
    ' open and say why instead of showing a dead view.
    if m.liveTvChannels = invalid or m.liveTvChannels.count() = 0 then
        LiveTvSetStatus("No channels loaded yet - the lineup is still fetching. Try GRID again in a moment, or BACK to browse.")
        return
    end if
    if m.liveTvGridRoot = invalid then
        m.liveTvGridRoot = CreateObject("roSGNode", "Group")
        m.liveTvGridRoot.visible = false
        ' Appended last = topmost, so the grid covers the browse panels, the
        ' preview video and the info card while it is up.
        m.top.appendChild(m.liveTvGridRoot)
    end if
    m.liveTvGridOpen = true
    m.liveTvGridRoot.visible = true
    if m.liveTvBrowseGroup <> invalid then m.liveTvBrowseGroup.visible = false
    if m.liveTvGenreList <> invalid then m.liveTvGenreList.setFocus(false)
    if m.liveTvChannelList <> invalid then m.liveTvChannelList.setFocus(false)
    ' CLAIM THE ZONE AND THE FOCUS. This used to do neither, which is why the
    ' grid was unusable from the genre list: the zone stayed "channels", so
    ' onKeyEvent never routed keys to LiveTvGridKey and the frozen grid could
    ' not be scrolled; and with focus removed from both lists and no focusable
    ' node inside the grid, NOTHING had focus, so key presses went nowhere at
    ' all. Pressing OK then fell through to the channel list, which tuned a
    ' channel instead of locking onto the guide.
    ' The grid is drawn entirely from plain Rectangles/Labels, so there is no
    ' child to focus; focusing the scene group itself is the established way
    ' to keep its onKeyEvent in the loop (same call PlaybackScene uses).
    if m.liveTvZone <> "grid" then
        m.liveTvZoneBeforeGrid = m.liveTvZone
    end if
    m.liveTvZone = "grid"
    ' Same-press guard, ONLY for the rail path. The old comment here claimed
    ' the select key "can still arrive as an "ok"" for the grid - that is what
    ' the dead lowercase comparison in LiveTvGridKey was built on, and Roku
    ' does not deliver a lowercase select key at all. The INFO path opens the
    ' grid on a different key entirely, so arming the guard there swallowed
    ' the first OK the user pressed inside the guide, which reads as "the
    ' grid is frozen" all over again. Mirrors m.liveTvIgnoreNextOk.
    m.liveTvIgnoreNextGridOk = openedBySelect
    st = m.liveTvGridState
    if st = invalid then
        st = {}
        m.liveTvGridState = st
    end if
    ' Any runtime error inside the build (bad guide record, node limit,
    ' layout AA missing) used to bubble out of the key handler as a modal
    ' BrightScript error dialog: the app looked completely frozen with no way
    ' back except a remote kill. Degrade to a status message + closed grid
    ' instead, and leave the diagnostic in the log.
    try
        LiveTvGridClear(st, m.liveTvGridRoot)
        LiveTvGridBuild(st, m.liveTvGridRoot, m.liveTvChannels, m.liveTvEpg, 0)
        ' Open on whatever is currently tuned so the grid lands in context.
        LiveTvGridCenterOn(st, m.liveTvTunedIdx)
        ' Focus the scene group so the grid actually receives keys.
        m.top.setFocus(true)
    catch e
        ? "GRID open failed: " + LiveTvGridErrorText(e)
        m.liveTvGridOpen = false
        if m.liveTvGridRoot <> invalid then m.liveTvGridRoot.visible = false
        if m.liveTvBrowseGroup <> invalid then m.liveTvBrowseGroup.visible = true
        ' Hand the zone and focus back, otherwise a failed draw leaves the
        ' scene claiming "grid" with nothing focused - the same dead state
        ' this block is meant to avoid.
        m.liveTvZone = m.liveTvZoneBeforeGrid
        if m.liveTvZone = invalid or m.liveTvZone = "" or m.liveTvZone = "grid" then m.liveTvZone = "channels"
        LiveTvFocusZone()
        LiveTvSetStatus("The grid could not be drawn. Press BACK and try again.")
        return
    end try
    nch = 0
    if st.channels <> invalid then nch = st.channels.count()
    nprog = 0
    if st.epg <> invalid then nprog = st.epg.count()
    ? "GRID open channels=" + nch.ToStr() + " epg=" + nprog.ToStr() + " rows=" + st.rows.count().ToStr() + " blocks=" + st.blocks.count().ToStr() + " withProgs=" + st.withProgs.ToStr()
    LiveTvSetStatus("GRID  -  Up/Down channel  -  Left/Right time  -  OK watch  -  Back exit")
end sub

sub LiveTvGridCloseView()
    m.liveTvGridOpen = false
    if m.liveTvGridRoot <> invalid then
        LiveTvGridClear(m.liveTvGridState, m.liveTvGridRoot)
        m.liveTvGridRoot.visible = false
    end if
    if m.liveTvBrowseGroup <> invalid then m.liveTvBrowseGroup.visible = true
end sub

' Center the grid cursor on a channel index (used on open).
sub LiveTvGridCenterOn(st as Object, idx as Integer)
    if st = invalid then return
    total = 0
    if st.channels <> invalid then total = st.channels.count()
    if total = 0 then return
    if idx < 0 then idx = 0
    if idx >= total then idx = 0
    st.focus = idx
    st.first = LiveTvGridClampFirst(st, idx)
    LiveTvGridRenderRows(st)
end sub

' Grid key handling. Returns true when the key was consumed.
function LiveTvGridKey(key as String) as Boolean
    st = m.liveTvGridState
    if st = invalid then return false
    if key = "up" then
        LiveTvGridFocusStep(st, -1)
        return true
    else if key = "down" then
        LiveTvGridFocusStep(st, 1)
        return true
    else if key = "left" then
        LiveTvGridScrollTime(st, -30)
        return true
    else if key = "right" then
        LiveTvGridScrollTime(st, 30)
        return true
    ' UPPERCASE "OK", like every other comparison in this scene. This branch
    ' read `key = "ok"`, and Roku delivers the select key as "OK" - the
    ' lowercase literal never matched, so the OK branch was dead code:
    ' LiveTvGridKey fell through to `return false`, onKeyEvent returned false,
    ' and the select key went to SceneGraph default handling with no tune
    ' behind it. The guide opened and looked frozen. LiveTvIsNavKey (line
    ' ~2342) and the fullscreen branch in onKeyEvent both already used "OK",
    ' which is what made the lowercase literal a typo rather than a
    ' deliberate second spelling.
    else if key = "OK" then
        ' Swallow the OK that opened the grid so the guide does not instantly
        ' tune whatever channel it happened to centre on.
        if m.liveTvIgnoreNextGridOk = true then
            m.liveTvIgnoreNextGridOk = false
            ? "LIVETV grid open-OK consumed (no tune)"
            return true
        end if
        ch = LiveTvGridFocusChannel(st)
        if ch <> invalid then
            idx = st.focus
            m.liveTvIgnoreNextGridOk = false
            ' ORDER MATTERS: move the channel list's cursor FIRST, while the
            ' grid still owns the screen. jumpToItem fires itemFocused, and
            ' LiveTvOnChannelFocused's grid guard drops that event instead of
            ' re-tuning behind the guide. Closing the grid and focusing FIRST
            ' landed focus on whatever row the list was still showing, then
            ' jumped again - two focus events, and the second one raced the
            ' tune the first one had already started.
            LiveTvSelectChannel(idx, true)
            LiveTvGridCloseView()
            m.liveTvZone = "channels"
            LiveTvFocusZone()
        end if
        return true
    end if
    return false
end function

' ------------------------------------------------------------------
' Rendering: genre rail (left) + channel guide (middle)
' ------------------------------------------------------------------

sub LiveTvRenderGenres()
    if m.liveTvGenreList = invalid then return
    m.liveTvGenreIds = []
    m.liveTvSyncing = true
    content = CreateObject("roSGNode", "ContentNode")
    defs = LiveTvRailDefs()
    freeCount = m.liveTvFreeChannels.count()
    for each def in defs
        ' Hide buckets the current feed does not fill: an empty "(0)" rail
        ' entry reads as broken. Synthetic entries always show.
        if not LiveTvIsSyntheticGenre(def.id) and LiveTvGenreCount(def.id) = 0 then
            continue for
        end if
        nd = content.createChild("ContentNode")
        if def.id = "grid" then
            ' A view, not a genre: no "(n)" count.
            nd.title = def.label
        else if def.id = "all" then
            nd.title = def.label + "  (" + freeCount.ToStr() + ")"
        else if def.id = "premium" then
            if m.liveTvPremiumChannels.count() > 0 then
                nd.title = def.label + "  (" + m.liveTvPremiumChannels.count().ToStr() + ")"
            else
                nd.title = def.label
            end if
        else if def.id = "sudo" then
            ' FEATURE 2: same pattern as premium - no bare "(0)" before the
            ' background lineup lands.
            if m.liveTvSudoChannels.count() > 0 then
                nd.title = def.label + "  (" + m.liveTvSudoChannels.count().ToStr() + ")"
            else
                nd.title = def.label
            end if
        else
            nd.title = def.label + "  (" + LiveTvGenreCount(def.id).ToStr() + ")"
        end if
        m.liveTvGenreIds.Push(def.id)
    end for
    m.liveTvGenreList.content = content
    ? "LIVETV rail defs=" + defs.count().ToStr() + " visible=" + m.liveTvGenreIds.count().ToStr() + " ids=" + m.liveTvGenreIds.Join(",")
    m.liveTvSyncing = false
end sub

' Move the left rail highlight to a genre id without firing the selection
' handler (m.liveTvSyncing guard, same rule as the other programmatic jumps).
sub LiveTvSyncGenreRail(genreId as String)
    if m.liveTvGenreList = invalid then return
    if m.liveTvGenreIds = invalid then return
    for i = 0 to m.liveTvGenreIds.count() - 1
        if m.liveTvGenreIds[i] = genreId then
            m.liveTvSyncing = true
            m.liveTvGenreList.jumpToItem = i
            m.liveTvSyncing = false
            return
        end if
    end for
end sub

function LiveTvGenreCount(genreId as String) as Integer
    ' FEATURE 2: the virtual channel lives outside the free lineup.
    if genreId = "sudo" then return m.liveTvSudoChannels.count()
    n = 0
    for each ch in m.liveTvFreeChannels
        if type(ch) = "roAssociativeArray" and LiveTvGenreIdOf(ch) = genreId then
            n = n + 1
        end if
    end for
    return n
end function

' Point m.liveTvChannels at the current genre and render the middle list.
' Premium renders empty + kicks the fetch if not loaded yet.
sub LiveTvShowGenreList()
    if m.liveTvGenre = "grid" then
        ' View swap, not a channel filter. The rail path switches the state to
        ' "all" first, so the grid, the channel list behind it and the rail all
        ' agree on the same index space - otherwise OK in the grid selected an
        ' index from the all-channel lineup against a filtered genre list.
        m.liveTvGenre = "all"
        m.liveTvChannels = m.liveTvFreeChannels
        LiveTvSyncGenreRail("all")
        LiveTvUpdateGuideHeader()
        LiveTvRenderChannels()
        LiveTvGridOpenView(true)
        return
    end if
    if m.liveTvGridOpen then
        LiveTvGridCloseView()
    end if
    if m.liveTvGenre = "sudo" then
        ' FEATURE 2: the virtual channel renders on its own rail entry and
        ' never triggers any background lineup fetch.
        m.liveTvChannels = m.liveTvSudoChannels
    else if m.liveTvGenre = "premium" then
        ' Premium (cinevid) is dormant for now - the rail no longer offers it.
        ' Keep the branch so a stray stored genre cannot fall through to the
        ' free/genre filters and render something misleading.
        m.liveTvChannels = []
    else if m.liveTvGenre = "all" then
        ' Free lineup only: premium is switched off for now.
        m.liveTvChannels = m.liveTvFreeChannels
    else
        filtered = []
        for each ch in m.liveTvFreeChannels
            if type(ch) = "roAssociativeArray" and LiveTvGenreIdOf(ch) = m.liveTvGenre then
                filtered.Push(ch)
            end if
        end for
        m.liveTvChannels = filtered
    end if
    LiveTvUpdateGuideHeader()
    LiveTvRenderChannels()
end sub

sub LiveTvUpdateGuideHeader()
    if m.liveTvGuideHeader = invalid then return
    label = "ALL CHANNELS"
    defs = LiveTvCanonicalGenres()
    for each def in defs
        if def.id = m.liveTvGenre then
            label = UCase(def.label)
            exit for
        end if
    end for
    if m.liveTvChannels.count() > 0 then
        label = label + "  -  " + m.liveTvChannels.count().ToStr() + " CHANNELS"
    else if m.liveTvGenre = "premium" then
        label = label + "  -  LOADING..."
    end if
    m.liveTvGuideHeader.text = label
end sub

sub LiveTvRenderChannels()
    if m.liveTvChannelList = invalid then return
    m.liveTvSyncing = true
    m.liveTvRowsBoundary = 0
    content = CreateObject("roSGNode", "ContentNode")
    for each ch in m.liveTvChannels
        if type(ch) = "roAssociativeArray" then
            nd = content.createChild("ContentNode")
            num = LiveTvChanNumText(ch)
            nd.title = SafeStr(ch, "title", "Channel")
            nd.shortDescriptionLine1 = num
            ' NOW and NEXT on separate lines, formatted by the scene so the
            ' custom row component can draw them in two places (the old
            ' single-string LabelList could never do that).
            nowP = LiveTvNowProg(ch)
            nextP = LiveTvNextProg(ch)
            ' Earliest "now" programme end across the rendered rows: the clock
            ' tick re-renders exactly when one of these labels goes stale.
            if nowP <> invalid then
                pStopB = LiveTvToInt(SafeGet(nowP, "stop", 0))
                if pStopB > 0 then
                    if m.liveTvRowsBoundary = 0 or pStopB < m.liveTvRowsBoundary then m.liveTvRowsBoundary = pStopB
                end if
            end if
            if SafeStr(ch, "source", "") = "cinevid" then
                cat = SafeStr(ch, "genre", "")
                facts = LiveTvPremiumFacts(ch)
                if facts <> "" then
                    nd.shortDescriptionLine2 = "NOW   " + facts
                else if cat <> "" then
                    nd.shortDescriptionLine2 = "NOW   " + UCase(cat)
                else
                    nd.shortDescriptionLine2 = "NOW   Live"
                end if
                nd.description = "NEXT   Continuous 24/7"
            else if SafeStr(ch, "source", "") = "sudo" then
                nt = LiveTvProgTitle(nowP)
                if nt <> "" then
                    nd.shortDescriptionLine2 = "NOW   " + LiveTvProgTime(nowP) + "   " + nt
                else
                    nd.shortDescriptionLine2 = "NOW   Sudo Movies"
                end if
                nxt = LiveTvProgTitle(nextP)
                if nxt <> "" then
                    nd.description = "NEXT   " + LiveTvProgTime(nextP) + "   " + nxt
                else
                    ' Build from the queue directly if the epg snapshot is empty
                    nt2 = ""
                    if m.liveTvSudoMovies <> invalid and m.liveTvSudoMovies.count() > 0 then
                        nidx = (m.liveTvSudoIdx + 1) mod m.liveTvSudoMovies.count()
                        mv = m.liveTvSudoMovies[nidx]
                        if mv <> invalid and type(mv) = "roAssociativeArray" then
                            nt2 = SafeStr(mv, "title", "")
                        end if
                    end if
                    if nt2 <> "" then
                        nd.description = "NEXT   Up next   " + nt2
                    else
                        nd.description = "NEXT   Up next"
                    end if
                end if
            else
                nt = LiveTvProgTitle(nowP)
                if nt <> "" then
                    nd.shortDescriptionLine2 = "NOW   " + LiveTvProgTime(nowP) + "   " + nt
                else
                    cat = SafeStr(ch, "genre", "")
                    if cat <> "" then
                        nd.shortDescriptionLine2 = "NOW   On now   " + UCase(cat)
                    else
                        nd.shortDescriptionLine2 = "NOW   On now"
                    end if
                end if
                nxt = LiveTvProgTitle(nextP)
                if nxt <> "" then
                    nd.description = "NEXT   " + LiveTvProgTime(nextP) + "   " + nxt
                else
                    nd.description = "NEXT   Nothing scheduled"
                end if
            end if
        else
            nd = content.createChild("ContentNode")
            nd.title = "Channel"
            nd.shortDescriptionLine1 = ""
            nd.shortDescriptionLine2 = ""
            nd.description = ""
        end if
    end for
    m.liveTvChannelList.content = content
    m.liveTvSyncing = false
    if m.liveTvRowsBoundary = 0 or m.liveTvRowsBoundary <= LiveTvNowSec() then
        m.liveTvRowsBoundary = LiveTvNowSec() + 1800
    end if
end sub

' Re-render the guide rows at a programme boundary without moving the user's
' cursor. Used by the clock tick so NOW/NEXT labels stop showing a show that
' has already ended.
sub LiveTvRefreshRowsForClock()
    idx = m.liveTvIndex
    LiveTvRenderChannels()
    if m.liveTvChannelList <> invalid then
        m.liveTvSyncing = true
        m.liveTvChannelList.jumpToItem = idx
        m.liveTvSyncing = false
    end if
    LiveTvUpdateInfo()
end sub

' Push fresh channels/guide data into an open grid and repaint its rows.
sub LiveTvGridRefreshData()
    if not m.liveTvGridOpen then return
    st = m.liveTvGridState
    if st = invalid then return
    st.epg = m.liveTvEpg
    if m.liveTvChannels <> invalid then st.channels = m.liveTvChannels
    st.now = LiveTvNowSec()
    LiveTvGridRenderRows(st)
end sub

function LiveTvChanNumText(ch as Object) as String
    if ch = invalid then return ""
    n = SafeStr(ch, "chNo", "")
    if n = "" then n = SafeStr(ch, "chno", "")
    if n = "" then return ""
    ' Only numeric channel numbers get a badge. Premium category tags read
    ' as plain labels on the custom row (kept visible by the row).
    if LiveTvItemIsNumeric(n) then return n
    return n
end function

function LiveTvItemIsNumeric(s as String) as Boolean
    if s = invalid or s = "" then return false
    for i = 1 to s.Len()
        code = Asc(Mid(s, i, 1))
        if code < 48 or code > 57 then return false
    end for
    return true
end function

' One guide row: sequential CH number, then the channel name, then the
' current program with its start time (free, from the XMLTV guide) or the
' curated category tag (premium). Time-first so "what's on now" reads
' before the program title.
function LiveTvChannelLine(ch as Object) as String
    line = "CH " + SafeStr(ch, "chNo", "1")
    line = line + "   " + SafeStr(ch, "title", "Channel")
    if SafeStr(ch, "source", "") = "cinevid" then
        cat = SafeStr(ch, "genre", "")
        if cat <> "" then line = line + "   -   " + UCase(cat)
        return line
    end if
    nowP = LiveTvNowProg(ch)
    if nowP <> invalid then
        t = LiveTvProgTitle(nowP)
        if t <> "" then
            tm = LiveTvEpochClock(SafeGet(nowP, "start", 0))
            line = line + "   -   " + tm + "  " + t
        end if
    end if
    return line
end function

' ------------------------------------------------------------------
' Selection + info panel
' ------------------------------------------------------------------

sub LiveTvSelectChannel(idx as Integer, doTune as Boolean)
    total = m.liveTvChannels.count()
    if total = 0 then return
    if idx < 0 then idx = 0
    if idx >= total then idx = total - 1
    m.liveTvIndex = idx
    m.liveTvSyncing = true
    if m.liveTvChannelList <> invalid then
        m.liveTvChannelList.jumpToItem = idx
    end if
    m.liveTvSyncing = false
    LiveTvUpdateInfo()
    if doTune then LiveTvTune(idx, false)
end sub

' Genre picked on the left rail: swap the middle list and tune its first
' channel. Focus moves to the channel list (rail is one OK away via LEFT).
sub LiveTvOnGenrePicked()
      if m.liveTvGenreList = invalid then return
      ' Same reason as LiveTvOnChannelPicked: a straggler event from the list
      ' must not re-enter LiveTvShowGenreList and rebuild the grid underneath
      ' a user who is already scrolling it.
      if m.liveTvGridOpen then
          ? "LIVETV genre pick ignored (grid open)"
          return
      end if
      if m.liveTvSyncing then return
    idx = m.liveTvGenreList.itemSelected
    if idx = invalid then return
    if idx < 0 or idx >= m.liveTvGenreIds.count() then return
    LiveTvSelectGenre(m.liveTvGenreIds[idx])
end sub

sub LiveTvSelectGenre(genreId as String)
    m.liveTvGenre = genreId
    LiveTvStopSurf()
    m.liveTvIndex = 0
    m.liveTvTunedIdx = -1
    if m.liveTvPreview <> invalid then m.liveTvPreview.control = "stop"
    LiveTvHideError()
    ' Self-heal (task-drop guard): a genre switch during the lineup/EPG phase
    ' can leave the free fetch half-done, so restart whichever piece is
    ' missing (premium no longer participates in this flow).
    if m.liveTvFreeChannels.count() = 0 and m.liveTvPhase <> "channels" and m.liveTvPhase <> "sudo" then
        LiveTvLoadData()
    else if m.liveTvFreeChannels.count() > 0 and m.liveTvEpg.count() = 0 and m.liveTvPhase <> "epg" and m.liveTvPhase <> "sudo" then
        LiveTvLoadEpgData()
    end if
    ' FEATURE 2 self-heal: the sudo fetch runs after the guide, so a genre
    ' switch that lands here first restarts it instead of showing an empty row.
    if genreId = "sudo" and m.liveTvSudoChannels.count() = 0 and m.liveTvPhase <> "sudo" then
        LiveTvLoadSudoData()
    end if
    if genreId = "sudo" then
        ' Keep the on-air movie + fabricated guide aligned with the wall clock
        ' before the list/info card reads them.
        m.liveTvSudoIdx = LiveTvSudoSchedule().idx
        LiveTvEnsureSudoEpg()
    end if
    if genreId = "grid" then
        ' Full-screen grid: no channel tune, no list focus. The grid builds
        ' from whatever lineup the previous genre left loaded.
        LiveTvShowGenreList()
        return
    end if
    LiveTvShowGenreList()
    m.liveTvZone = "channels"
    LiveTvSetStatus("Up/Down surf  •  OK fullscreen  •  Back exit")
    if m.liveTvChannels.count() > 0 then
        LiveTvSelectChannel(0, true)
    end if
    if m.liveTvChannelList <> invalid then m.liveTvChannelList.setFocus(true)
end sub

' Per-channel fact line for a PREMIUM (cinevid) channel: category, language
' and country as the CineVid index actually publishes them. Shared by the
' browse info card and the fullscreen banner so both show the same real
' values instead of an identical placeholder sentence.
function LiveTvPremiumFacts(ch as Object) as String
    if ch = invalid then return ""
    cat = SafeStr(ch, "genre", "")
    if cat <> "" then cat = UCase(cat)
    lang = SafeStr(ch, "language", "")
    country = SafeStr(ch, "country", "")
    facts = cat
    if lang <> "" then
        if facts <> "" then facts = facts + "  •  " + lang
        else facts = lang
    end if
    if country <> "" then
        if facts <> "" then facts = facts + "  •  " + UCase(country)
        else facts = UCase(country)
    end if
    return facts
end function

' Compact "NOW WATCHING" panel, top right of the browse screen.
'
' Deliberately separate from the big info card lower down: the card is a
' large panel you read when you stop and look, this is the small always-on
' answer to "what is this, and how far in are we?". It sits in the gap
' between the LIVE badge (ends x=472) and the clock (starts x=1600), and it
' is hidden while the grid is up because the grid draws its own header,
' clock and NOW playhead across that whole strip.
'
' Built at runtime rather than declared in the XML so the geometry is
' explicit and cannot silently collapse to a zero-extent node.
sub LiveTvBuildNowWatching()
    if m.liveTvNowPanel <> invalid then return
    panel = CreateObject("roSGNode", "Group")
    plate = CreateObject("roSGNode", "Rectangle")
    plate.color = "0x0B0E17E6"
    plate.width = 1060
    plate.height = 112
    plate.translation = "[520,22]"
    panel.appendChild(plate)
    edge = CreateObject("roSGNode", "Rectangle")
    edge.color = "0xD42028FF"
    edge.width = 5
    edge.height = 112
    edge.translation = "[520,22]"
    panel.appendChild(edge)
    track = CreateObject("roSGNode", "Rectangle")
    track.color = "0xFFFFFF1F"
    track.width = 1060
    track.height = 3
    track.translation = "[520,131]"
    panel.appendChild(track)
    fill = CreateObject("roSGNode", "Rectangle")
    fill.color = "0xD42028FF"
    fill.width = 0
    fill.height = 3
    fill.translation = "[520,131]"
    panel.appendChild(fill)
    m.liveTvNowFill = fill

    kicker = CreateObject("roSGNode", "Label")
    kicker.color = "0xD42028FF"
    kicker.font = "font:SmallSystemFont"
    kicker.width = 320
    kicker.height = 22
    kicker.translation = "[544,28]"
    kicker.text = "NOW WATCHING"
    panel.appendChild(kicker)

    num = CreateObject("roSGNode", "Label")
    num.color = "0xFFFFFFFF"
    num.font = "font:LargeBoldSystemFont"
    num.width = 96
    num.height = 44
    num.translation = "[544,52]"
    panel.appendChild(num)

    name = CreateObject("roSGNode", "Label")
    name.color = "0xFFFFFFFF"
    name.font = "font:MediumBoldSystemFont"
    name.width = 900
    name.height = 40
    name.vertAlign = "center"
    name.translation = "[646,54]"
    panel.appendChild(name)

    prog = CreateObject("roSGNode", "Label")
    prog.color = "0xE5E7EBFF"
    prog.font = "font:MediumSystemFont"
    prog.width = 920
    ' No maxLines: it is not available on every Roku OS level, and a fixed
    ' height clips a long programme title on its own.
    prog.height = 32
    prog.translation = "[544,98]"
    panel.appendChild(prog)

    tm = CreateObject("roSGNode", "Label")
    tm.color = "0x9CA3AFFF"
    tm.font = "font:SmallSystemFont"
    tm.width = 440
    tm.height = 22
    tm.horizAlign = "right"
    tm.translation = "[1120,30]"
    panel.appendChild(tm)

    m.liveTvNowPanel = panel
    m.liveTvNowKicker = kicker
    m.liveTvNowNum = num
    m.liveTvNowName = name
    m.liveTvNowProg = prog
    m.liveTvNowTime = tm
    m.top.appendChild(panel)
end sub

sub LiveTvUpdateNowWatching()
    LiveTvBuildNowWatching()
    if m.liveTvNowPanel = invalid then return
    if m.liveTvZone = "grid" then
        m.liveTvNowPanel.visible = false
        return
    end if
    m.liveTvNowPanel.visible = true
    ch = LiveTvCurrentChannel()
    if ch = invalid then
        if m.liveTvNowNum <> invalid then m.liveTvNowNum.text = "--"
        if m.liveTvNowName <> invalid then m.liveTvNowName.text = "Nothing tuned"
        if m.liveTvNowProg <> invalid then m.liveTvNowProg.text = "Choose a channel to start watching"
        if m.liveTvNowTime <> invalid then m.liveTvNowTime.text = ""
        if m.liveTvNowFill <> invalid then m.liveTvNowFill.width = 0
        return
    end if
    if m.liveTvNowNum <> invalid then m.liveTvNowNum.text = SafeStr(ch, "chNo", "")
    if m.liveTvNowName <> invalid then m.liveTvNowName.text = LiveTvGridChanName(ch)
    nowSec = LiveTvNowSec()
    if SafeStr(ch, "source", "") = "cinevid" then
        ' Premium rows have no schedule, so there is no progress to draw and
        ' no time range to print - show the facts the index really publishes.
        facts = LiveTvPremiumFacts(ch)
        if m.liveTvNowProg <> invalid then
            if facts <> "" then
                m.liveTvNowProg.text = facts
            else
                m.liveTvNowProg.text = "Continuous live channel"
            end if
        end if
        if m.liveTvNowTime <> invalid then m.liveTvNowTime.text = "24/7"
        if m.liveTvNowFill <> invalid then m.liveTvNowFill.width = 0
        return
    end if
    nowP = LiveTvNowProg(ch)
    if m.liveTvNowProg <> invalid then
        t = LiveTvProgTitle(nowP)
        if t <> "" then
            m.liveTvNowProg.text = t
        else
            cat = SafeStr(ch, "genre", "")
            if cat <> "" then
                m.liveTvNowProg.text = "Live " + LCase(cat) + " channel"
            else
                m.liveTvNowProg.text = "Live channel"
            end if
        end if
    end if
    pStart = 0
    pStop = 0
    if nowP <> invalid then
        pStart = LiveTvToInt(SafeGet(nowP, "start", 0))
        pStop = LiveTvToInt(SafeGet(nowP, "stop", 0))
    end if
    if m.liveTvNowTime <> invalid then
        if pStart > 0 and pStop > pStart then
            m.liveTvNowTime.text = LiveTvClockOfDay(pStart) + " - " + LiveTvClockOfDay(pStop)
        else
            m.liveTvNowTime.text = LiveTvClockOfDay(nowSec)
        end if
    end if
    if m.liveTvNowFill <> invalid then
        pct = 0
        if pStart > 0 and pStop > pStart then
            pct = Int((nowSec - pStart) * 100 / (pStop - pStart))
        end if
        if pct < 0 then pct = 0
        if pct > 100 then pct = 100
        m.liveTvNowFill.width = Int(1060 * pct / 100)
    end if
end sub

sub LiveTvUpdateInfo()
    LiveTvUpdateNowWatching()
    ch = LiveTvCurrentChannel()
    if ch = invalid then return
    if m.liveTvInfoName <> invalid then
        m.liveTvInfoName.text = SafeStr(ch, "title", "Channel")
    end if
    nowP = LiveTvNowProg(ch)
    nextP = LiveTvNextProg(ch)
    if m.liveTvInfoTrack <> invalid then m.liveTvInfoTrack.visible = false
    if m.liveTvInfoFill <> invalid then m.liveTvInfoFill.visible = false
    if m.liveTvInfoNowMeta <> invalid then m.liveTvInfoNowMeta.visible = true
    if m.liveTvInfoNextMeta <> invalid then m.liveTvInfoNextMeta.visible = true
    src = SafeStr(ch, "source", "")
    if src = "cinevid" then
        cat = SafeStr(ch, "genre", "")
        if cat <> "" then cat = UCase(cat)
        facts = LiveTvPremiumFacts(ch)
        if m.liveTvInfoNowMeta <> invalid then m.liveTvInfoNowMeta.text = "NOW"
        if m.liveTvInfoNow <> invalid then
            if facts <> "" then
                m.liveTvInfoNow.text = facts
            else if cat <> "" then
                m.liveTvInfoNow.text = cat + "  •  live"
            else
                m.liveTvInfoNow.text = "Live"
            end if
        end if
        if m.liveTvInfoNextMeta <> invalid then m.liveTvInfoNextMeta.text = "NEXT"
        if m.liveTvInfoNext <> invalid then
            m.liveTvInfoNext.text = "Continuous 24/7 stream"
        end if
        if m.liveTvInfoDesc <> invalid then
            d = SafeStr(ch, "description", "")
            if d = "" then
                if cat <> "" then
                    d = "Live " + LCase(cat) + " channel."
                else
                    d = "Live premium channel."
                end if
            end if
            m.liveTvInfoDesc.text = d
        end if
        return
    end if
    if src = "sudo" then
        nt = LiveTvProgTitle(nowP)
        ntm = ""
        if nowP <> invalid then ntm = LiveTvProgTime(nowP)
        if m.liveTvInfoNowMeta <> invalid then
            if ntm <> "" then
                m.liveTvInfoNowMeta.text = "NOW   " + ntm
            else
                m.liveTvInfoNowMeta.text = "NOW"
            end if
        end if
        if m.liveTvInfoNow <> invalid then
            if nt <> "" then
                m.liveTvInfoNow.text = nt
            else
                m.liveTvInfoNow.text = "Sudo Movies"
            end if
        end if
        if m.liveTvInfoTrack <> invalid then
            m.liveTvInfoTrack.visible = true
            if m.liveTvInfoFill <> invalid then
                m.liveTvInfoFill.visible = true
                m.liveTvInfoFill.width = 0
            end if
        end if
        nxt = LiveTvProgTitle(nextP)
        nxtm = ""
        if nextP <> invalid then nxtm = LiveTvProgTime(nextP)
        if m.liveTvInfoNextMeta <> invalid then
            if nxtm <> "" then
                m.liveTvInfoNextMeta.text = "NEXT   " + nxtm
            else
                m.liveTvInfoNextMeta.text = "NEXT"
            end if
        end if
        if m.liveTvInfoNext <> invalid then
            if nxt <> "" then
                m.liveTvInfoNext.text = nxt
            else
                nt2 = ""
                if m.liveTvSudoMovies <> invalid and m.liveTvSudoMovies.count() > 0 then
                    nidx = (m.liveTvSudoIdx + 1) mod m.liveTvSudoMovies.count()
                    mv = m.liveTvSudoMovies[nidx]
                    if mv <> invalid and type(mv) = "roAssociativeArray" then
                        nt2 = SafeStr(mv, "title", "")
                    end if
                end if
                if nt2 <> "" then
                    m.liveTvInfoNext.text = nt2
                else
                    m.liveTvInfoNext.text = "Up next"
                end if
            end if
        end if
        if m.liveTvInfoDesc <> invalid then
            d = LiveTvNowDesc(ch)
            if d = "" then d = "A continuous stream of trending movies."
            m.liveTvInfoDesc.text = d
        end if
        return
    end if
    cat = SafeStr(ch, "genre", "")
    if cat <> "" then cat = UCase(cat)
    chDesc = SafeStr(ch, "description", "")
    nowP2 = LiveTvNowProg(ch)
    nextP2 = LiveTvNextProg(ch)
    nt = LiveTvProgTitle(nowP2)
    ntm = ""
    if nowP2 <> invalid then ntm = LiveTvProgTime(nowP2)
    if m.liveTvInfoNowMeta <> invalid then
        if ntm <> "" then
            m.liveTvInfoNowMeta.text = "NOW   " + ntm
        else
            m.liveTvInfoNowMeta.text = "NOW"
        end if
    end if
    if m.liveTvInfoNow <> invalid then
        if nt <> "" then
            m.liveTvInfoNow.text = nt
        else if cat <> "" then
            m.liveTvInfoNow.text = cat
        else
            m.liveTvInfoNow.text = "On now"
        end if
    end if
    if m.liveTvInfoTrack <> invalid then
        m.liveTvInfoTrack.visible = true
        if m.liveTvInfoFill <> invalid then
            m.liveTvInfoFill.visible = true
            pStart = 0
            pStop = 0
            if nowP2 <> invalid then
                pStart = LiveTvToInt(SafeGet(nowP2, "start", 0))
                pStop = LiveTvToInt(SafeGet(nowP2, "stop", 0))
            end if
            pct = 0
            nowSec = LiveTvNowSec()
            if pStart > 0 and pStop > pStart then
                pct = Int((nowSec - pStart) * 100 / (pStop - pStart))
            end if
            if pct < 0 then pct = 0
            if pct > 100 then pct = 100
            m.liveTvInfoFill.width = Int(646 * pct / 100)
        end if
    end if
    nxt = LiveTvProgTitle(nextP2)
    nxtm = ""
    if nextP2 <> invalid then nxtm = LiveTvProgTime(nextP2)
    if m.liveTvInfoNextMeta <> invalid then
        if nxtm <> "" then
            m.liveTvInfoNextMeta.text = "NEXT   " + nxtm
        else
            m.liveTvInfoNextMeta.text = "NEXT"
        end if
    end if
    if m.liveTvInfoNext <> invalid then
        if nxt <> "" then
            m.liveTvInfoNext.text = nxt
        else
            m.liveTvInfoNext.text = "Nothing scheduled"
        end if
    end if
    if m.liveTvInfoDesc <> invalid then
        d = LiveTvNowDesc(ch)
        if d = "" then d = chDesc
        if d = "" and cat <> "" then
            d = "Live " + LCase(cat) + " channel."
        end if
        if d = "" then
            d = "Live stream."
        end if
        m.liveTvInfoDesc.text = d
    end if
end sub

function LiveTvCurrentChannel() as Object
    if m.liveTvChannels.count() = 0 then return invalid
    idx = m.liveTvIndex
    if idx < 0 then idx = 0
    if idx >= m.liveTvChannels.count() then idx = m.liveTvChannels.count() - 1
    ch = m.liveTvChannels[idx]
    if type(ch) <> "roAssociativeArray" then return invalid
    return ch
end function

function LiveTvEpgEntry(ch as Object) as Object
    if ch = invalid then return invalid
    key = SafeStr(ch, "epgId", "")
    if key = "" then key = SafeStr(ch, "id", "")
    if key = "" then return invalid
    if m.liveTvEpg = invalid then return invalid
    e = m.liveTvEpg[key]
    if type(e) = "roAssociativeArray" then return e
    ' Name-based fallback: the Streaming TV Guides fallback source keys the
    ' EPG by NORMALIZED channel name (both lineups derive from Samsung's
    ' guide data, so names match after normalization). Only tried when the
    ' primary epgId lookup missed, so XMLTV keys stay authoritative.
    name = SafeStr(ch, "title", "")
    if name <> "" then
        nk = LiveTvStvgNormKey(name)
        if nk <> "" then
            e = m.liveTvEpg[nk]
            if type(e) = "roAssociativeArray" then return e
        end if
    end if
    return invalid
end function

' Now/next for one channel, computed FRESH at the wall clock.
'
' The merged guide map carries a { now, next } snapshot taken when the data
' arrived. Printing that snapshot is only correct for the first programme:
' once it ends, "now" is a finished show and "next" is the show that is
' actually on air - the stale "up next" card. Recompute from the programme
' list every time instead, and keep the snapshot as a last resort for a
' record whose list did not survive the cross-thread copy.
function LiveTvNowNextFor(ch as Object) as Object
    out = { now: invalid, next: invalid, next2: invalid }
    if ch = invalid or type(ch) <> "roAssociativeArray" then return out
    e = LiveTvEpgEntry(ch)
    if e <> invalid and type(e) = "roAssociativeArray" then
        progs = e.programs
        if type(progs) = "roArray" and progs.count() > 0 then
            sn = LiveTvNowNextAt(progs, LiveTvNowSec())
            out.now = sn.now
            out.next = sn.next
            out.next2 = sn.next2
            if LiveTvProgTitle(out.now) <> "" or LiveTvProgTitle(out.next) <> "" then
                return out
            end if
        end if
    end if
    ' Channel record fallback: the lineup index ships its own [[epoch, title]]
    ' list, and it travels in the same channels field the list renders from.
    raw = LiveTvGridNormalizePrograms(SafeGet(ch, "programs", invalid))
    if type(raw) = "roArray" and raw.count() > 0 then
        sn = LiveTvNowNextAt(raw, LiveTvNowSec())
        out.now = sn.now
        out.next = sn.next
        out.next2 = sn.next2
        if LiveTvProgTitle(out.now) <> "" or LiveTvProgTitle(out.next) <> "" then
            return out
        end if
    end if
    ' Last resort: the snapshot.
    if e <> invalid and type(e) = "roAssociativeArray" then
        if type(e.now) = "roAssociativeArray" and LiveTvProgTitle(e.now) <> "" then out.now = e.now
        arr = e.next
        if arr <> invalid and type(arr) = "roArray" then
            if arr.count() > 0 and type(arr[0]) = "roAssociativeArray" then out.next = arr[0]
            if arr.count() > 1 and type(arr[1]) = "roAssociativeArray" then out.next2 = arr[1]
        end if
    end if
    return out
end function

function LiveTvNowProg(ch as Object) as Object
    nn = LiveTvNowNextFor(ch)
    if nn = invalid then return invalid
    return nn.now
end function

function LiveTvNextProg(ch as Object) as Object
    nn = LiveTvNowNextFor(ch)
    if nn = invalid then return invalid
    return nn.next
end function

function LiveTvProgTitle(prog as Object) as String
    if prog = invalid then return ""
    if type(prog) <> "roAssociativeArray" then return ""
    return SafeStr(prog, "title", "")
end function

' Description lives on the windowed programs list, not on now/next:
' match the now program by start time.
function LiveTvNowDesc(ch as Object) as String
    nn = LiveTvNowNextFor(ch)
    if nn <> invalid and nn.now <> invalid and type(nn.now) = "roAssociativeArray" then
        d = SafeStr(nn.now, "desc", "")
        if d <> "" then return d
    end if
    e = LiveTvEpgEntry(ch)
    if e = invalid then return ""
    nowP = LiveTvNowProg(ch)
    if nowP = invalid then return ""
    nowStart = SafeGet(nowP, "start", 0)
    progs = e.programs
    if progs = invalid or type(progs) <> "roArray" then return ""
    for each p in progs
        if p <> invalid and type(p) = "roAssociativeArray" then
            if SafeGet(p, "start", -1) = nowStart then
                return SafeStr(p, "desc", "")
            end if
        end if
    end for
    return ""
end function

function LiveTvProgTime(prog as Object) as String
    if prog = invalid then return ""
    if type(prog) <> "roAssociativeArray" then return ""
    s = LiveTvEpochClock(SafeGet(prog, "start", 0))
    stopV = 0
    if prog.DoesExist("stop") then stopV = prog["stop"]
    e = LiveTvEpochClock(stopV)
    if s <> "" and e <> "" then return s + "-" + e
    if s <> "" then return s
    return ""
end function

function LiveTvEpochClock(epoch as Object) as String
    sec = 0
    if epoch <> invalid then
        if type(epoch) = "roInt" or type(epoch) = "Integer" then
            sec = epoch
        else if type(epoch) = "roString" or type(epoch) = "String" then
            return epoch
        end if
    end if
    if sec <= 0 then return ""
    dt = CreateObject("roDateTime")
    dt.FromSeconds(sec)
    dt.ToLocalTime()
    h = dt.GetHours()
    min = dt.GetMinutes()
    suffix = "AM"
    if h >= 12 then suffix = "PM"
    h12 = h mod 12
    if h12 = 0 then h12 = 12
    minStr = min.ToStr()
    if min < 10 then minStr = "0" + minStr
    return h12.ToStr() + ":" + minStr + " " + suffix
end function

' ------------------------------------------------------------------
' Focus observers: surfing the guide retunes the preview, debounced by
' surfTimer (0.4s) so key-repeat on a long list does not fire-storm the
' video plane with stop/start cycles.
' ------------------------------------------------------------------

sub LiveTvOnChannelFocused()
    if m.liveTvSyncing then return
    ' Zone guard (audit finding): a stray itemFocused while fullscreen must
    ' never flip the zone out from under the fullscreen key handling.
    if m.liveTvZone = "fullscreen" then return
    ' Same guard LiveTvOnChannelPicked and LiveTvOnGenrePicked already carry.
    ' Selecting a row in the grid moves the channel list's cursor, and
    ' jumpToItem fires itemFocused: without this, the OK that opens a channel
    ' from the guide re-enters the browse tune path behind the grid, so the
    ' grid and the player fight over the same channel.
    if m.liveTvGridOpen then
        ? "LIVETV channel focus ignored (grid open)"
        return
    end if
    if m.liveTvChannelList = invalid then return
    idx = m.liveTvChannelList.itemFocused
    if idx = invalid then return
    if idx < 0 or idx >= m.liveTvChannels.count() then return
    m.liveTvZone = "channels"
    m.liveTvIndex = idx
    LiveTvUpdateInfo()
    m.liveTvSurfIdx = idx
    if m.liveTvSurfTimer <> invalid then
        m.liveTvSurfTimer.control = "stop"
        m.liveTvSurfTimer.control = "start"
    end if
end sub

sub LiveTvOnSurfSettled()
    if m.liveTvClosed then return
    if m.liveTvZone = "fullscreen" then return
    idx = m.liveTvSurfIdx
    if idx = invalid then return
    if idx < 0 or idx >= m.liveTvChannels.count() then return
    LiveTvTune(idx, false)
end sub

sub LiveTvStopSurf()
    if m.liveTvSurfTimer <> invalid then m.liveTvSurfTimer.control = "stop"
    m.liveTvSurfIdx = -1
end sub

sub LiveTvOnChannelPicked()
      ' While the guide is up it owns the screen. A late itemSelected from the
      ' channel list would otherwise reset the zone to "channels" and tune,
      ' which is exactly the "it tunes instead of locking onto the grid"
      ' behaviour: the list fires the event even after focus was taken away.
      if m.liveTvGridOpen then
          ? "LIVETV channel pick ignored (grid open)"
          return
      end if
      if m.liveTvChannels.count() = 0 then return
    m.liveTvZone = "channels"
    ? "LIVETV picked channel -> fullscreen"
    LiveTvStopSurf()
    ' OK must fullscreen the HIGHLIGHTED channel. Surf tuning is debounced,
    ' so the tuned pointer can lag the focused row: retune first when they
    ' diverge. (Premium re-resolves a fresh token inside fullscreen replay;
    ' the extra resolve here is stopped by that replay's own start.)
    if m.liveTvIndex <> m.liveTvTunedIdx then
        LiveTvTune(m.liveTvIndex, false)
        if m.liveTvTunedIdx < 0 then
            ' Tune failed outright (error banner is up): stay in browse.
            return
        end if
    end if
    LiveTvEnterFullscreen()
end sub

' ------------------------------------------------------------------
' Tuning: stop previous stream before every retune; a failed tune
' auto-tries the next channel (up to 3 attempts) before showing a
' clear error and staying on the guide (never hang, never exit).
' ------------------------------------------------------------------

sub LiveTvTune(idx as Integer, isAutoRetry as Boolean)
    if m.liveTvVideo = invalid then return
    if idx < 0 or idx >= m.liveTvChannels.count() then return
    ch = m.liveTvChannels[idx]
    if type(ch) <> "roAssociativeArray" then return
    if not isAutoRetry then m.liveTvTuneFails = 0
    ' Premium records carry url "" BY DESIGN (the stream is resolved per
    ' tune, see LiveTvStartChannelPlayback); the no-URL guard only applies
    ' to the free FAST lineup.
    isCinevid = (SafeStr(ch, "source", "") = "cinevid")
    isSudo = (SafeStr(ch, "source", "") = "sudo")
    if not isCinevid and not isSudo and SafeStr(ch, "url", "") = "" then
        if isAutoRetry then
            LiveTvAutoRetry()
        else
            LiveTvFailCurrent("This channel has no stream URL. Try another channel.")
        end if
        return
    end if
    if idx = m.liveTvTunedIdx then return
    LiveTvStartChannelPlayback(idx, ch)
end sub

' Stop any current playback and start channel idx from scratch: sets the
' tuned pointer + tune watchdog first, then plays the free FAST url
' directly or kicks off a fresh premium resolve. Shared by tuning, zapping
' and fullscreen replay — every call is a fresh playback session (which
' the fullscreen node swap depends on, see the fullscreen section).
sub LiveTvStartChannelPlayback(idx as Integer, ch as Object)
    if m.liveTvVideo = invalid then return
    m.liveTvTunedIdx = idx
    ' New tuning intent: the grace window restarts with the channel, and so
    ' does the premium-resolve deferral budget.
    m.liveTvWatchdogRearms = 0
    m.liveTvResolveDefers = 0
    if m.liveTvPreview <> invalid then m.liveTvPreview.control = "stop"
    if m.liveTvFsVideo <> invalid then m.liveTvFsVideo.control = "stop"
    m.liveTvVideo.control = "stop"
    LiveTvHideError()
    LiveTvSetStatus("Tuning " + SafeStr(ch, "title", "channel") + "...")
    if m.liveTvTuneTimer <> invalid then m.liveTvTuneTimer.control = "start"
    ' FEATURE 2: the virtual channel resolves the current queue movie via
    ' VixSrc (task thread) instead of playing a static URL.
    if SafeStr(ch, "source", "") = "sudo" then
        LiveTvStartSudoMovie(idx, true)
        if m.liveTvZone = "fullscreen" then LiveTvShowFsBanner()
        return
    end if
    ' A sudo resolve still in flight must never land on a non-sudo tune:
    ' stop it here so a late movie can never clobber this channel's stream.
    LiveTvStopSudoResolveTask()
    if m.liveTvZone = "fullscreen" then LiveTvShowFsBanner()
    if SafeStr(ch, "source", "") = "cinevid" then
        LiveTvStartResolve(ch)
        return
    end if
    url = SafeStr(ch, "url", "")
    if url = "" then
        LiveTvFailCurrent("This channel has no stream URL. Try another channel.")
        return
    end if
    LiveTvPlayUrl(url, ch)
end sub

' Build a fresh playback session on the active video node for an
' already-resolved URL (free lineups resolve inline; premium arrives here
' via the resolve observer).
sub LiveTvPlayUrl(url as String, ch as Object)
    if m.liveTvVideo = invalid then return
    if url = invalid or url = "" then
        ? "LIVETV play skipped: empty url for " + LiveTvGridChanName(ch)
        LiveTvAutoRetry()
        return
    end if
    content = CreateObject("roSGNode", "ContentNode")
    content.url = url
    ' BOTH sources are HLS, so "hls" is declared unconditionally:
    '   - free:  i.mjh.nz per-channel playlist (.m3u8)
    '   - premium: cinevid.st /stream/{token}, which serves
    '     Content-Type application/vnd.apple.mpegurl (a real HLS playlist)
    '     but has NO file extension - verified 2026-09-26. An extension test
    '     ("only set hls when the url contains .m3u8") therefore matches the
    '     free lineup and silently drops the format on EVERY premium channel,
    '     which is the opposite of what it was meant to do. Keep it constant.
    content.streamFormat = "hls"
    t = SafeStr(ch, "title", "")
    if t <> "" then content.title = t
    m.liveTvVideo.content = content
    m.liveTvVideo.control = "play"
end sub

' ------------------------------------------------------------------
' Premium (cinevid) per-tune stream resolution. Tokens are short-lived, so
' every tune/replay resolves a FRESH token through LiveTvTask mode
' "resolve" (see CineVid.brs header) — resolving on the render thread is
' impossible (roUrlTransfer is task-thread-only).
' ------------------------------------------------------------------

sub LiveTvStartResolve(ch as Object)
    LiveTvStopResolveTask()
    ' A new resolve gets the full deferral budget. LiveTvStartChannelPlayback
    ' already clears this, but a resolve is only meaningful with a fresh
    ' allowance, so keep the reset next to the resolve itself.
    m.liveTvResolveDefers = 0
    chanId = SafeStr(ch, "id", "")
    if chanId = "" then
        ' No resolvable id: count as a failed tune and move on (bounded).
        LiveTvAutoRetry()
        return
    end if
    task = CreateObject("roSGNode", "LiveTvTask")
    if task = invalid then
        LiveTvAutoRetry()
        return
    end if
    m.liveTvResolveTask = task
    task.observeField("resolveStatus", "LiveTvOnResolveStatus")
    task.mode = "resolve"
    task.resolveId = chanId
    ? "LIVETV resolve start id=" + chanId
    task.control = "run"
end sub

sub LiveTvStopResolveTask()
    if m.liveTvResolveTask <> invalid then
        m.liveTvResolveTask.control = "stop"
        m.liveTvResolveTask = invalid
    end if
end sub

' A late completion for an abandoned resolve must never play: the event is
' dropped unless it comes from the CURRENT resolve task.
' NODE COMPARISON RULE: `=`/`<>` on two nodes throws &h18 on this firmware —
' invalid-check first, then isSameNode().
sub LiveTvOnResolveStatus(evt as Object)
    if m.liveTvClosed then return
    task = evt.getRoSGNode()
    if task = invalid then return
    current = m.liveTvResolveTask
    if current = invalid then return
    if not task.isSameNode(current) then return
    st = task.resolveStatus
    if st = invalid or st = 0 then return
    url = task.resolvedUrl
    ' Read the task's own reason BEFORE dropping the ref: the resolve failure
    ' path used to be completely silent, so a premium channel that answers
    ' { success:false } just produced a black screen and an unexplained zap.
    reason = ""
    if task.hasField("resolveError") then
        r = task.getField("resolveError")
        if r <> invalid then reason = r
    end if
    LiveTvStopResolveTask()
    if st = 200 and url <> "" then
        m.liveTvResolveReason = ""
        idx = m.liveTvTunedIdx
        if idx < 0 or idx >= m.liveTvChannels.count() then return
        ch = m.liveTvChannels[idx]
        if type(ch) <> "roAssociativeArray" then return
        LiveTvPlayUrl(url, ch)
        return
    end if
    m.liveTvResolveReason = reason
    ' Resolve failures count as tune failures: offline premium channels are
    ' common ({ success:false } with HTTP 200), so the bounded auto-retry
    ' zaps to the next channel instead of hanging on a dead one.
    LiveTvAutoRetry()
end sub

' ------------------------------------------------------------------
' FEATURE 2: Sudo Movies queue playback. The tuned virtual channel plays
' the movie at m.liveTvSudoIdx; each resolve goes through LiveTvTask mode
' "sudoresolve" (VixSrc pattern, task thread only). Unresolvable movies are
' skipped bounded by the queue length: never hang, never exit the guide.
' ------------------------------------------------------------------

function LiveTvTunedIsSudo() as Boolean
    idx = m.liveTvTunedIdx
    if idx = invalid or idx < 0 or idx >= m.liveTvChannels.count() then return false
    ch = m.liveTvChannels[idx]
    if type(ch) <> "roAssociativeArray" then return false
    return SafeStr(ch, "source", "") = "sudo"
end function

' Wall-clock schedule for the artificial-live channel: which movie slot is
' "on air" right now (idx), when it started (slotStart), and how far into
' it we are (offset). The anchor is a FIXED past epoch (init), so the
' schedule is identical on every visit - it never resets. slotIdx wraps
' over the queue length (queue size varies day to day).
function LiveTvSudoSchedule() as Object
    now = LiveTvNowSec()
    total = m.liveTvSudoMovies.count()
    if total <= 0 then total = 1
    slots = (now - m.liveTvSudoAnchor) \ 7200
    if slots < 0 then slots = 0
    slotStart = m.liveTvSudoAnchor + slots * 7200
    return { idx: slots mod total, slotStart: slotStart, offset: now - slotStart }
end function

' Rebuild the fabricated Sudo Movies guide from the CURRENT queue + fixed
' anchor, then merge it into m.liveTvEpg. The task publishes the same shape,
' but a cache written by an older build (or a queue that arrived before the
' scene's anchor was known) can leave the guide misaligned - and then the
' up-next card names a movie the channel is not actually about to play.
' Cheap (queue length is <= 20) and idempotent, so it is safe to call on
' every genre switch / task arrival.
sub LiveTvEnsureSudoEpg()
    n = m.liveTvSudoMovies.count()
    if n <= 0 then return
    now = LiveTvNowSec()
    slots = (now - m.liveTvSudoAnchor) \ 7200
    if slots < 0 then slots = 0
    idx0 = slots mod n
    programs = []
    for i = 0 to n - 1
        mv = m.liveTvSudoMovies[(idx0 + i) mod n]
        st2 = m.liveTvSudoAnchor + (slots + i) * 7200
        prog = { title: LiveTvSudoMovieTitle(mv), start: st2, desc: LiveTvSudoMovieDesc(mv) }
        prog["stop"] = st2 + 7200
        programs.Push(prog)
    end for
    if type(m.liveTvEpg) <> "roAssociativeArray" then m.liveTvEpg = {}
    m.liveTvEpg["sudo-movies"] = { programs: programs }
    ? "LIVETV sudo epg synced slots=" + slots.ToStr() + " idx0=" + idx0.ToStr() + " n=" + n.ToStr()
end sub

function LiveTvSudoMovieTitle(mv as Object) as String
    if mv = invalid or type(mv) <> "roAssociativeArray" then return "Movie"
    return SafeStr(mv, "title", "Movie")
end function

function LiveTvSudoMovieDesc(mv as Object) as String
    if mv = invalid or type(mv) <> "roAssociativeArray" then return ""
    yr = SafeStr(mv, "year", "")
    ov = SafeStr(mv, "overview", "")
    if ov.Len() > 180 then ov = Left(ov, 180) + "..."
    if yr <> "" and ov <> "" then return "(" + yr + ") " + ov
    if ov <> "" then return ov
    if yr <> "" then return "Trending movie (" + yr + ")."
    return "Trending movie from Sudo Movies."
end function

sub LiveTvStartSudoMovie(idx as Integer, syncToClock as Boolean)
    LiveTvStopSudoResolveTask()
    ' New movie, new tune: drop any stale live-join guard so an unrelated
    ' error can't be mistaken for a seek that overshot the runtime.
    m.liveTvSudoJoinSeeking = false
    total = m.liveTvSudoMovies.count()
    if total = 0 then
        ' Queue not loaded yet: bounded, move on like any dead tune.
        LiveTvAutoRetry()
        return
    end if
    if syncToClock then
        ' ARTIFICIAL LIVE join: the wall clock picks the movie and the seek
        ' offset, so visiting anytime lands mid-program like cable. Near the
        ' slot end (last minute) take the NEXT slot fresh from its start.
        sched = LiveTvSudoSchedule()
        if sched.offset >= 7200 - 60 then
            m.liveTvSudoIdx = (sched.idx + 1) mod total
            m.liveTvSudoSlotStart = sched.slotStart + 7200
            m.liveTvSudoSeekTo = 0
        else
            m.liveTvSudoIdx = sched.idx
            m.liveTvSudoSlotStart = sched.slotStart
            m.liveTvSudoSeekTo = sched.offset
        end if
    else
        ' Skip/advance: play the chosen movie fresh from its start.
        m.liveTvSudoSeekTo = 0
        m.liveTvSudoSlotStart = LiveTvNowSec()
    end if
    if m.liveTvSudoIdx < 0 or m.liveTvSudoIdx >= m.liveTvSudoMovies.count() then m.liveTvSudoIdx = 0
    movie = m.liveTvSudoMovies[m.liveTvSudoIdx]
    tmdbId = SafeStr(movie, "tmdbId", "")
    if tmdbId = "" then
        LiveTvSudoSkip()
        return
    end if
    task = CreateObject("roSGNode", "LiveTvTask")
    if task = invalid then
        LiveTvSudoSkip()
        return
    end if
    m.liveTvSudoTask = task
    task.observeField("resolveStatus", "LiveTvOnSudoResolveStatus")
    task.mode = "sudoresolve"
    task.resolveId = tmdbId
    ? "LIVETV sudo resolve start tmdb=" + tmdbId
    task.control = "run"
end sub

sub LiveTvStopSudoResolveTask()
    if m.liveTvSudoTask <> invalid then
        m.liveTvSudoTask.control = "stop"
        m.liveTvSudoTask = invalid
    end if
end sub

' Late completions for an abandoned movie resolve must never play: dropped
' unless from the CURRENT sudo task (same isSameNode rule as premium).
sub LiveTvOnSudoResolveStatus(evt as Object)
    if m.liveTvClosed then return
    task = evt.getRoSGNode()
    if task = invalid then return
    current = m.liveTvSudoTask
    if current = invalid then return
    if not task.isSameNode(current) then return
    st = task.resolveStatus
    if st = invalid or st = 0 then return
    url = task.resolvedUrl
    LiveTvStopSudoResolveTask()
    if st = 200 and url <> "" then
        m.liveTvSudoSkips = 0
        ' Late-completion guard: if the user left the sudo channel while this
        ' resolve was in flight (genre switch, auto-retry zap), the movie must
        ' never play over a non-sudo channel - drop the event instead.
        if not LiveTvTunedIsSudo() then return
        idx = m.liveTvTunedIdx
        if idx < 0 or idx >= m.liveTvChannels.count() then return
        ch = m.liveTvChannels[idx]
        if type(ch) <> "roAssociativeArray" then return
        LiveTvSudoSyncEpg(m.liveTvSudoSlotStart)
        LiveTvPlayUrl(url, ch)
        return
    end if
    LiveTvSudoSkip()
end sub

' Skip to the next queue movie. Bounded by the queue length: once every
' movie has been tried, stop and hand off to the standard auto-retry (which
' zaps to the next channel, or shows the error after 3 dead tunes).
sub LiveTvSudoSkip()
    if m.liveTvClosed then return
    total = m.liveTvSudoMovies.count()
    if total = 0 then
        LiveTvAutoRetry()
        return
    end if
    m.liveTvSudoSkips = m.liveTvSudoSkips + 1
    if m.liveTvSudoSkips > total then
        m.liveTvSudoSkips = 0
        LiveTvAutoRetry()
        return
    end if
    m.liveTvSudoIdx = m.liveTvSudoIdx + 1
    if m.liveTvSudoIdx >= total then m.liveTvSudoIdx = 0
    idx = m.liveTvTunedIdx
    if idx < 0 or idx >= m.liveTvChannels.count() then return
    LiveTvStartSudoMovie(idx, false)
end sub

' Advance to the next movie when the current one ends (Video "finished").
' Works on the preview AND fullscreen nodes - whoever fired the event owns
' m.liveTvVideo already. Wraps the queue; the EPG re-anchors below.
sub LiveTvSudoAdvance()
    if m.liveTvClosed then return
    total = m.liveTvSudoMovies.count()
    if total = 0 then return
    m.liveTvSudoSkips = 0
    m.liveTvSudoIdx = m.liveTvSudoIdx + 1
    if m.liveTvSudoIdx >= total then m.liveTvSudoIdx = 0
    idx = m.liveTvTunedIdx
    if idx < 0 or idx >= m.liveTvChannels.count() then return
    ch = m.liveTvChannels[idx]
    if type(ch) <> "roAssociativeArray" then return
    LiveTvStartChannelPlayback(idx, ch)
end sub

' Re-anchor the fabricated sudo guide. pivot = the artificial-live slot
' start on a fresh join (the NOW program began there — joining mid-slot
' shows the true live time), or the advance moment after a movie ends.
' Keeps the channel row, the info card and the fullscreen banner truthful
' across advances and wraps without refetching.
sub LiveTvSudoSyncEpg(pivot as Integer)
    total = m.liveTvSudoMovies.count()
    if total = 0 then return
    if m.liveTvSudoChannels.count() = 0 then return
    ch = m.liveTvSudoChannels[0]
    if type(ch) <> "roAssociativeArray" then return
    key = SafeStr(ch, "epgId", "")
    if key = "" then key = SafeStr(ch, "id", "")
    if key = "" then return
    if m.liveTvSudoIdx < 0 or m.liveTvSudoIdx >= total then m.liveTvSudoIdx = 0
    ' pivot comes from the caller: artificial-live slot start on a fresh
    ' join (NOW truly began there), or the advance moment after a movie
    ' ends. Guard a bogus/zero pivot to the wall clock.
    if pivot <= 0 then pivot = LiveTvNowSec()
    programs = []
    for k = 0 to total - 1
        mv = m.liveTvSudoMovies[(m.liveTvSudoIdx + k) mod total]
        st2 = pivot + k * 7200
        en2 = st2 + 7200
        desc = SafeStr(mv, "year", "")
        ov = SafeStr(mv, "overview", "")
        if ov.Len() > 180 then ov = Left(ov, 180) + "..."
        if desc <> "" and ov <> "" then
            desc = "(" + desc + ") " + ov
        else if ov <> "" then
            desc = ov
        else if desc <> "" then
            desc = "Trending movie (" + desc + ")."
        else
            desc = "Trending movie from Sudo Movies."
        end if
        prog = { title: SafeStr(mv, "title", "Movie"), start: st2, desc: desc }
        prog["stop"] = en2
        programs.Push(prog)
    end for
    snap = LiveTvNowNext(programs, pivot)
    m.liveTvEpg[key] = { programs: programs, now: snap.now, next: snap.next }
    LiveTvUpdateInfo()
    if m.liveTvZone = "fullscreen" then LiveTvShowFsBanner()
end sub

' ------------------------------------------------------------------
' FEATURE 1: cable-style fullscreen info banner. Stock Rectangles + Labels
' (XML-declared above), dark panel + red accent matching the guide theme.
' Shown on fullscreen enter and every zap via the StartChannelPlayback hook
' (zone = "fullscreen"); auto-hides ~6s after via bannerTimer. BACK and OK
' exit semantics are untouched; Up/Down zap keeps working and refreshes it.
' Missing EPG degrades to channel + clock with a "No program info" line.
' ------------------------------------------------------------------

sub LiveTvOnBannerTimeout()
    LiveTvHideFsBanner()
end sub

sub LiveTvHideFsBanner()
    if m.liveTvBannerTimer <> invalid then m.liveTvBannerTimer.control = "stop"
    if m.liveTvFsBanner <> invalid then m.liveTvFsBanner.visible = false
end sub

function LiveTvClockStr() as String
    dt = CreateObject("roDateTime")
    dt.ToLocalTime()
    h = dt.GetHours()
    min = dt.GetMinutes()
    suffix = "AM"
    if h >= 12 then suffix = "PM"
    h12 = h mod 12
    if h12 = 0 then h12 = 12
    minStr = min.ToStr()
    if min < 10 then minStr = "0" + minStr
    return h12.ToStr() + ":" + minStr + " " + suffix
end function

sub LiveTvFillFsBanner()
    if m.liveTvFsBanner = invalid then return
    if m.liveTvZone <> "fullscreen" then return
    ch = LiveTvCurrentChannel()
    if ch = invalid then return
    if m.liveTvFsBannerChan <> invalid then
        m.liveTvFsBannerChan.text = "CH " + SafeStr(ch, "chNo", "1") + "   " + SafeStr(ch, "title", "Channel")
    end if
    if m.liveTvFsBannerClock <> invalid then
        m.liveTvFsBannerClock.text = LiveTvClockStr()
    end if
    src = SafeStr(ch, "source", "")
    if src = "cinevid" then
        facts = LiveTvPremiumFacts(ch)
        if m.liveTvFsBannerNowMeta <> invalid then
            m.liveTvFsBannerNowMeta.text = "NOW"
            m.liveTvFsBannerNowMeta.visible = true
        end if
        if m.liveTvFsBannerNow <> invalid then
            if facts <> "" then
                m.liveTvFsBannerNow.text = facts
            else
                cat = SafeStr(ch, "genre", "")
                if cat <> "" then
                    m.liveTvFsBannerNow.text = UCase(cat)
                else
                    m.liveTvFsBannerNow.text = "Live"
                end if
            end if
        end if
        if m.liveTvFsBannerNextMeta <> invalid then
            m.liveTvFsBannerNextMeta.text = "NEXT"
            m.liveTvFsBannerNextMeta.visible = true
        end if
        if m.liveTvFsBannerNext <> invalid then
            m.liveTvFsBannerNext.text = "Continuous 24/7 stream"
        end if
        if m.liveTvFsBannerDesc <> invalid then
            d = SafeStr(ch, "description", "")
            if d = "" then
                cat = SafeStr(ch, "genre", "")
                if cat <> "" then
                    d = "Live " + LCase(cat) + " channel."
                else
                    d = "Live premium channel."
                end if
            end if
            m.liveTvFsBannerDesc.text = d
        end if
    else if src = "sudo" then
        nowP = LiveTvNowProg(ch)
        nextP = LiveTvNextProg(ch)
        nt = LiveTvProgTitle(nowP)
        ntm = ""
        if nowP <> invalid then ntm = LiveTvProgTime(nowP)
        if m.liveTvFsBannerNowMeta <> invalid then
            if ntm <> "" then
                m.liveTvFsBannerNowMeta.text = "NOW   " + ntm
            else
                m.liveTvFsBannerNowMeta.text = "NOW"
            end if
            m.liveTvFsBannerNowMeta.visible = true
        end if
        if m.liveTvFsBannerNow <> invalid then
            if nt <> "" then
                m.liveTvFsBannerNow.text = nt
            else
                m.liveTvFsBannerNow.text = "Sudo Movies"
            end if
        end if
        nxt = LiveTvProgTitle(nextP)
        nxtm = ""
        if nextP <> invalid then nxtm = LiveTvProgTime(nextP)
        if m.liveTvFsBannerNextMeta <> invalid then
            if nxtm <> "" then
                m.liveTvFsBannerNextMeta.text = "NEXT   " + nxtm
            else
                m.liveTvFsBannerNextMeta.text = "NEXT"
            end if
            m.liveTvFsBannerNextMeta.visible = true
        end if
        if m.liveTvFsBannerNext <> invalid then
            if nxt <> "" then
                m.liveTvFsBannerNext.text = nxt
            else
                nt2 = ""
                if m.liveTvSudoMovies <> invalid and m.liveTvSudoMovies.count() > 0 then
                    nidx = (m.liveTvSudoIdx + 1) mod m.liveTvSudoMovies.count()
                    mv = m.liveTvSudoMovies[nidx]
                    if mv <> invalid and type(mv) = "roAssociativeArray" then
                        nt2 = SafeStr(mv, "title", "")
                    end if
                end if
                if nt2 <> "" then
                    m.liveTvFsBannerNext.text = nt2
                else
                    m.liveTvFsBannerNext.text = "Up next"
                end if
            end if
        end if
        if m.liveTvFsBannerDesc <> invalid then
            d = LiveTvNowDesc(ch)
            if d = "" then d = "Trending movies, live in rotation."
            m.liveTvFsBannerDesc.text = d
        end if
    else
        nowP = LiveTvNowProg(ch)
        nextP = LiveTvNextProg(ch)
        cat = SafeStr(ch, "genre", "")
        if cat <> "" then cat = UCase(cat)
        chDesc = SafeStr(ch, "description", "")
        nt = LiveTvProgTitle(nowP)
        ntm = ""
        if nowP <> invalid then ntm = LiveTvProgTime(nowP)
        if m.liveTvFsBannerNowMeta <> invalid then
            if ntm <> "" then
                m.liveTvFsBannerNowMeta.text = "NOW   " + ntm
            else
                m.liveTvFsBannerNowMeta.text = "NOW"
            end if
            m.liveTvFsBannerNowMeta.visible = true
        end if
        if m.liveTvFsBannerNow <> invalid then
            if nt <> "" then
                m.liveTvFsBannerNow.text = nt
            else if cat <> "" then
                m.liveTvFsBannerNow.text = "On now   " + cat
            else
                m.liveTvFsBannerNow.text = "On now"
            end if
        end if
        nxt = LiveTvProgTitle(nextP)
        nxtm = ""
        if nextP <> invalid then nxtm = LiveTvProgTime(nextP)
        if m.liveTvFsBannerNextMeta <> invalid then
            if nxtm <> "" then
                m.liveTvFsBannerNextMeta.text = "NEXT   " + nxtm
            else
                m.liveTvFsBannerNextMeta.text = "NEXT"
            end if
            m.liveTvFsBannerNextMeta.visible = true
        end if
        if m.liveTvFsBannerNext <> invalid then
            if nxt <> "" then
                m.liveTvFsBannerNext.text = nxt
            else
                m.liveTvFsBannerNext.text = "Nothing scheduled"
            end if
        end if
        if m.liveTvFsBannerDesc <> invalid then
            d = LiveTvNowDesc(ch)
            if d = "" then d = chDesc
            if d = "" and cat <> "" then d = "Live " + LCase(cat) + " channel."
            if d = "" then d = "Live stream."
            m.liveTvFsBannerDesc.text = d
        end if
    end if
end sub

' Show the fullscreen banner. Text is built by LiveTvFillFsBanner so the
' clock tick can refresh NOW/NEXT/progress in place WITHOUT restarting the
' 6s auto-hide timer (calling this wrapper from the tick would pin it open).
sub LiveTvShowFsBanner()
    LiveTvFillFsBanner()
    if m.liveTvFsBanner = invalid then return
    if m.liveTvZone <> "fullscreen" then return
    m.liveTvFsBanner.visible = true
    if m.liveTvBannerTimer <> invalid then
        m.liveTvBannerTimer.control = "stop"
        m.liveTvBannerTimer.control = "start"
    end if
end sub

sub LiveTvOnVideoState(evt as Object)
    if m.liveTvClosed then return
    state = evt.getData()
    if state = invalid then return
    if type(state) <> "roString" and type(state) <> "String" then state = state.ToStr()
    ? "LIVETV video state=" + state
    if state = "playing" then
        m.liveTvTuneFails = 0
        if m.liveTvTuneTimer <> invalid then m.liveTvTuneTimer.control = "stop"
        LiveTvHideError()
        ' A second "playing" after a live-join seek means the seek landed and
        ' playback survived it: clear the guard so a later error is a real
        ' dead tune, not a seek that overshot the runtime.
        m.liveTvSudoJoinSeeking = false
        ' ARTIFICIAL LIVE: join mid-program — seek once the video actually
        ' plays (a seek before buffering is ignored by the firmware). The
        ' offset is the wall-clock position inside the current 2h slot.
        if m.liveTvSudoSeekTo > 0 and m.liveTvVideo <> invalid then
            ? "LIVETV sudo live-join seek=" + m.liveTvSudoSeekTo.ToStr()
            m.liveTvVideo.seek = m.liveTvSudoSeekTo
            m.liveTvSudoJoinSeeking = true
        end if
        m.liveTvSudoSeekTo = 0
        if m.liveTvZone = "fullscreen" then
            LiveTvSetStatus("Up/Down zap  •  OK exit  •  Back browse")
        else
            LiveTvSetStatus("Up/Down surf  •  OK fullscreen  •  Back exit")
        end if
    else if state = "error" then
        ' Wall-clock joins can aim past the end of a short movie (the queue
        ' has no runtime field), which errors the seek. Replay that same movie
        ' from its start rather than zapping the user off the channel. The
        ' retry carries no seek, so a genuinely dead source still falls
        ' through to the normal auto-retry path below.
        if m.liveTvSudoJoinSeeking then
            m.liveTvSudoJoinSeeking = false
            ? "LIVETV sudo join-seek overshot - replaying from start"
            LiveTvStartSudoMovie(m.liveTvSudoIdx, false)
            return
        end if
        LiveTvAutoRetry()
    else if state = "stopped" then
        ' ARRIVE-AT-END vs DIED SILENTLY. "stopped" is ambiguous on this node:
        ' it is both what control="stop" leaves behind on every retune (the
        ' scene stops the old node before starting the new one) and what a
        ' stream that gave up mid-join reports. Retrying on it zapped the user
        ' off a channel that was merely changing, which is the
        ' buffering-then-stopped-to-next-channel behaviour being reported. So:
        ' never zap from here. Hand the decision to the tune watchdog, which
        ' already grants a bounded grace period and then fails the tune once.
        if m.liveTvTuneTimer <> invalid then m.liveTvTuneTimer.control = "start"
        ? "LIVETV video stopped - watchdog owns the retry, no zap"
    else if state = "finished" then
        ' FEATURE 2: the Sudo Movies queue plays back-to-back on whichever
        ' node is active (preview or fullscreen). Other sources keep the
        ' existing behavior (nothing).
        if LiveTvTunedIsSudo() then
            LiveTvSudoAdvance()
        end if
    end if
end sub

sub LiveTvOnTuneTimeout()
    if m.liveTvClosed then return
    if m.liveTvVideo = invalid then return
    ' A premium resolve is still running. The watchdog is 20s (tuneTimer in
    ' LiveTvScene.xml) but a cinevid resolve is allowed 25s before the task
    ' gives up, so the timer always fired FIRST, saw a node that had not been
    ' given any content yet, and called LiveTvAutoRetry - which zapped to the
    ' next channel mid-resolve. The user saw buffering -> stopped -> a violent
    ' walk down the channel list, which is why this looked like dead streams
    ' rather than a clock problem. Re-arm instead: the resolve's own
    ' resolveStatus event is what decides the outcome, and it now carries a
    ' reason (see LiveTvOnResolveStatus).
    '
    ' BOUNDED, or the deferral is its own hang. This re-arm was unconditional,
    ' and it only stops when LiveTvOnResolveStatus fires. If the task never
    ' posts that field - control="run" refused because the node is stopping,
    ' the thread wedged, the component failed to load - nothing ever calls
    ' LiveTvAutoRetry and the screen stays black with no message and no zap,
    ' forever. Two windows (40s) cover the 25s fetch budget with margin;
    ' after that the resolve is treated as a dead tune like any other, so the
    ' bounded retry path always runs.
    if m.liveTvResolveTask <> invalid then
        if m.liveTvResolveDefers >= 2 then
            ? "LIVETV tune watchdog gave up waiting for a resolve that never reported (defers=" + m.liveTvResolveDefers.ToStr() + ")"
            m.liveTvResolveDefers = 0
            LiveTvStopResolveTask()
            LiveTvAutoRetry()
            return
        end if
        m.liveTvResolveDefers = m.liveTvResolveDefers + 1
        ? "LIVETV tune watchdog deferred - resolve in flight " + m.liveTvResolveDefers.ToStr() + "/2"
        if m.liveTvTuneTimer <> invalid then m.liveTvTuneTimer.control = "start"
        return
    end if
    st = m.liveTvVideo.state
    if st = invalid then st = ""
    if type(st) <> "roString" and type(st) <> "String" then st = st.ToStr()
    ' "buffering" and "stopped" are not verdicts. Buffering is a stream that
    ' has not failed yet, and "stopped" is what this scene's own control="stop"
    ' leaves behind between one channel and the next - treating either as a
    ' dead tune is what turned a slow join into a zap. Give the stream a
    ' bounded grace period instead: each playback start resets the counter, so
    ' a channel gets two extra 20s windows (40s) to reach "playing" before it
    ' counts as a real failure. Bounded, so a stream that never reports
    ' anything still ends in the normal auto-retry rather than looping.
    if st = "playing" then return
    if st = "buffering" or st = "stopped" or st = "" then
        if m.liveTvWatchdogRearms < 2 then
            m.liveTvWatchdogRearms = m.liveTvWatchdogRearms + 1
            ? "LIVETV tune watchdog state=" + st + " grace=" + m.liveTvWatchdogRearms.ToStr() + "/2 - re-arming"
            if m.liveTvTuneTimer <> invalid then m.liveTvTuneTimer.control = "start"
            return
        end if
        ? "LIVETV tune watchdog state=" + st + " after 2 grace windows - treating as failed"
    end if
    LiveTvAutoRetry()
end sub

' Advance to the next channel after a failed tune. Bounded: after 3 total
' attempts the error is shown and auto-retrying stops. A manual zap or pick
' resets the counter (new tuning intent).
sub LiveTvAutoRetry()
    if m.liveTvClosed then return
    total = m.liveTvChannels.count()
    if total = 0 then return
    m.liveTvTuneFails = m.liveTvTuneFails + 1
    reason = m.liveTvResolveReason
    if reason = invalid then reason = ""
    if m.liveTvTuneFails >= 3 then
        m.liveTvTuneFails = 0
        ' A premium resolve that reached the server and was refused is a
        ' different problem from a dead network, so report the task's own
        ' reason instead of the generic network text when there is one.
        msg = "Could not tune 3 channels in a row - check your network, or press BACK and retry later."
        if reason <> "" then msg = reason
        LiveTvFailCurrent(msg)
        return
    end if
    nextIdx = m.liveTvIndex + 1
    if nextIdx >= total then nextIdx = 0
    if m.liveTvVideo <> invalid then m.liveTvVideo.control = "stop"
    LiveTvSetStatus("Channel unavailable - trying the next one (" + m.liveTvTuneFails.ToStr() + " of 3)...")
    LiveTvSelectChannel(nextIdx, false)
    LiveTvTune(nextIdx, true)
end sub

sub LiveTvFailCurrent(msg as String)
    if m.liveTvVideo <> invalid then m.liveTvVideo.control = "stop"
    if m.liveTvTuneTimer <> invalid then m.liveTvTuneTimer.control = "stop"
    m.liveTvTunedIdx = -1
    ' The error banner lives over the preview panel: leave fullscreen so
    ' the message is actually readable, then show it.
    if m.liveTvZone = "fullscreen" then
        ? "LIVETV exit-reason=fail msg=" + msg
        LiveTvExitFullscreen()
    end if
    if m.liveTvError <> invalid then
        m.liveTvError.text = msg
        m.liveTvError.visible = true
    end if
    if m.liveTvErrorBg <> invalid then m.liveTvErrorBg.visible = true
    if m.liveTvErrorAccent <> invalid then m.liveTvErrorAccent.visible = true
    LiveTvSetStatus(msg)
end sub

sub LiveTvHideError()
    if m.liveTvError <> invalid then m.liveTvError.visible = false
    if m.liveTvErrorBg <> invalid then m.liveTvErrorBg.visible = false
    if m.liveTvErrorAccent <> invalid then m.liveTvErrorAccent.visible = false
end sub

sub LiveTvSetStatus(msg as String)
    if m.liveTvStatus <> invalid then m.liveTvStatus.text = msg
end sub

' ------------------------------------------------------------------
' Fullscreen (v6): a FRESH bare Video created at enter, parented to m.top
' (this LiveTvScene group — scene-root parenting orphaned keys in v4),
' destroyed at exit. The opaque fsDim rectangle behind it is a
' diagnostic: dark screen + no picture = the compositor dropped the video
' plane; no change at all = the picked handler never fired.
' ------------------------------------------------------------------

sub LiveTvEnterFullscreen()
    if m.liveTvVideo = invalid then return
    if m.liveTvZone = "fullscreen" then return
    if m.liveTvZone <> "fullscreen" then m.liveTvZoneBeforeFs = m.liveTvZone
    LiveTvStopSurf()
    if m.liveTvBrowse <> invalid then m.liveTvBrowse.visible = false
    LiveTvSetChromeVisible(false)
    ' Dim stays OFF: it is an opaque fullscreen rect and a covering suspect
    ' for the black-screen reports (diagnostic value now lives in the logs).
    if m.liveTvFsDim <> invalid then m.liveTvFsDim.visible = false
    ? "LIVETV fullscreen enter (v8 xml-declared fs node)"
    ' v8: the fs player is XML-DECLARED inside this component (see
    ' LiveTvScene.xml fsVideo) — the only video pattern proven on this
    ' firmware (splash fullscreen, this scene's preview). Runtime-created
    ' Video nodes reached state=playing with no picture. The preview node
    ' is fully hidden AND its content released so the firmware video plane
    ' detaches from it (stop alone left the plane bound to the stopped
    ' preview while the fs node played blind). The fs node is also moved
    ' topmost so no opaque sibling can cover the picture.
    fs = m.top.findNode("fsVideo")
    if fs = invalid then
        ' Node missing: restore browse and bail instead of a dead screen.
        if m.liveTvBrowse <> invalid then m.liveTvBrowse.visible = true
        LiveTvSetChromeVisible(true)
        LiveTvSetStatus("Fullscreen player unavailable.")
        return
    end if
    ' unobserved while fullscreen (its late errors must not auto-retry
    ' the fullscreen channel), re-observed on exit.
    if m.liveTvPreview <> invalid then
        m.liveTvPreview.unobserveField("state")
        m.liveTvPreview.control = "stop"
        m.liveTvPreview.visible = false
    end if
    m.top.removeChild(fs)
    m.top.appendChild(fs)
    ' FEATURE 1 z-order: the fs move puts the video LAST (topmost) so no
    ' opaque sibling can cover the picture — but the banner group is then an
    ' earlier sibling UNDER the opaque video and would never show. Re-append
    ' it after the fs move so the banner stays the topmost sibling (cable
    ' banner renders over the picture, matching the hide-chrome model).
    if m.liveTvFsBanner <> invalid then
        m.top.removeChild(m.liveTvFsBanner)
        m.top.appendChild(m.liveTvFsBanner)
    end if
    fs.control = "stop"
    fs.visible = true
    ? "LIVETV fs node visible=" + fs.visible.ToStr() + " state=" + fs.state.ToStr()
    fs.observeField("state", "LiveTvOnVideoState")
    m.liveTvFsVideo = fs
    m.liveTvVideo = fs
    m.liveTvZone = "fullscreen"
    ' Same-press guard: the OK that fired itemSelected (enter) can also
    ' bubble to onKeyEvent as fullscreen+OK (instant exit = "flash").
    ' First OK in fullscreen is consumed, not honored.
    m.liveTvIgnoreNextOk = true
    fs.setFocus(true)
    if m.liveTvTunedIdx < 0 then
        ' Previous tune failed (tunedIdx reset): try the selected channel
        ' instead of replaying the dead one.
        LiveTvTune(m.liveTvIndex, false)
    else
        LiveTvReplayCurrent()
    end if
end sub

' Header chrome (top bar, title, LIVE badge, clock, status bar) sits under
' the video in z-order but the firmware video plane can composite below
' opaque siblings on some builds: hide ALL of it for a true fullscreen,
' restore on exit. Error labels stay browse-only (FailCurrent exits
' fullscreen before showing them).
sub LiveTvSetChromeVisible(visible as Boolean)
    ids = ["topBar", "topBarGlow", "topAccent", "headerTitle", "liveBadge", "liveBadgeGlow", "liveBadgeEdge", "liveBadgeLabel", "clockLabel", "statusBar", "statusTick", "statusLabel"]
    for each id in ids
        nd = m.top.findNode(id)
        if nd <> invalid then nd.visible = visible
    end for
end sub

sub LiveTvExitFullscreen()
    if m.liveTvPreview = invalid then return
    ' FEATURE 1: the banner is fullscreen-only.
    LiveTvHideFsBanner()
    if m.liveTvFsVideo <> invalid then
        m.liveTvFsVideo.control = "stop"
        m.liveTvFsVideo.unobserveField("state")
        ' v8: the fs node is XML-declared and persistent — hide it and
        ' release its content so the plane returns to the preview cleanly.
        m.liveTvFsVideo.content = invalid
        m.liveTvFsVideo.visible = false
    end if
    m.liveTvVideo = m.liveTvPreview
    if m.liveTvPreview <> invalid then
        m.liveTvPreview.visible = true
        m.liveTvPreview.observeField("state", "LiveTvOnVideoState")
    end if
    if m.liveTvFsDim <> invalid then m.liveTvFsDim.visible = false
    if m.liveTvBrowse <> invalid then m.liveTvBrowse.visible = true
    LiveTvSetChromeVisible(true)
    m.liveTvZone = m.liveTvZoneBeforeFs
    if m.liveTvZone <> "channels" then m.liveTvZone = "channels"
    if m.liveTvTunedIdx < 0 then
        ' Mirror the enter-side fallback: a failed fullscreen tune must not
        ' leave a dead preview behind (audit finding).
        LiveTvTune(m.liveTvIndex, false)
    else
        LiveTvReplayCurrent()
    end if
    LiveTvFocusZone()
end sub

' Replay the currently tuned channel with a FRESH ContentNode: re-assigning
' the same node is a field no-op, and only a new playback session makes the
' firmware video plane adopt the current node geometry (enter/exit
' fullscreen). Premium channels re-resolve a fresh token here; the shared
' starter also re-arms the tune guard so a stream stuck buffering in
' fullscreen can never hang.
sub LiveTvReplayCurrent()
    if m.liveTvVideo = invalid then return
    idx = m.liveTvTunedIdx
    if idx = invalid or idx < 0 or idx >= m.liveTvChannels.count() then return
    ch = m.liveTvChannels[idx]
    if type(ch) <> "roAssociativeArray" then return
    ? "LIVETV replay idx=" + idx.ToStr()
    LiveTvStartChannelPlayback(idx, ch)
end sub

sub LiveTvFocusZone()
    if m.liveTvZone = "genres" then
        if m.liveTvGenreList <> invalid then
            m.liveTvGenreList.setFocus(true)
            return
        end if
    end if
    m.liveTvZone = "channels"
    if m.liveTvChannelList <> invalid then m.liveTvChannelList.setFocus(true)
end sub

sub LiveTvZapStep(delta as Integer)
    total = m.liveTvChannels.count()
    if total = 0 then return
    idx = m.liveTvIndex + delta
    if idx < 0 then idx = 0
    if idx >= total then idx = total - 1
    LiveTvSelectChannel(idx, true)
end sub

' ------------------------------------------------------------------
' Clock
' ------------------------------------------------------------------

sub LiveTvOnClockTick()
    LiveTvUpdateClock()
    if m.liveTvPremiumTask <> invalid then
        LiveTvPremiumWatchdog()
    end if
    if m.liveTvGridOpen then
        ' Keeps the NOW playhead moving and follows the wall clock.
        LiveTvGridTick(m.liveTvGridState)
        return
    end if
    if m.liveTvZone = "fullscreen" then
        ' Refresh NOW/NEXT in place; do NOT restart the auto-hide timer.
        if m.liveTvFsBanner <> invalid and m.liveTvFsBanner.visible then
            LiveTvFillFsBanner()
        end if
        return
    end if
    ' Browse view: the up-next card and the row labels are computed from the
    ' guide snapshot at render time. Recompute them when the wall clock passes
    ' the earliest programme end so they never show a finished show.
    if m.liveTvRowsBoundary > 0 and LiveTvNowSec() >= m.liveTvRowsBoundary then
        LiveTvRefreshRowsForClock()
    else
        LiveTvUpdateInfo()
    end if
end sub

sub LiveTvUpdateClock()
    if m.liveTvClockLabel = invalid then return
    ' Fresh roDateTime is initialized to NOW: no Mark needed (MarkTime does
    ' not exist on roDateTime and crashed init with runtime error &hf4).
    m.liveTvClockLabel.text = LiveTvClockStr()
end sub

' ------------------------------------------------------------------
' Keys + teardown. Back unwinds: fullscreen -> browse -> home. Browse:
' LEFT from the channel guide opens the genre rail, RIGHT returns.
' ------------------------------------------------------------------

function LiveTvIsDigitKey(key as String) as Boolean
    if key = invalid then return false
    if Len(key) <> 1 then return false
    return key >= "0" and key <= "9"
end function

function LiveTvIsNavKey(key as String) as Boolean
    return key = "up" or key = "down" or key = "left" or key = "right" or key = "OK" or key = "back"
end function

' Type-ahead channel number entry. Jumps as soon as the typed digits match a
' channel exactly (so "1" -> 1, then "2" -> 12 when 12 exists); while only a
' prefix matches, the status bar shows the pending number. No timer: any
' navigation key clears the entry, which is what a user expects.
sub LiveTvNumEntry(digit as String)
    if m.liveTvNumEntry = invalid then m.liveTvNumEntry = ""
    entry = m.liveTvNumEntry + digit
    if Len(entry) > 3 then entry = digit
    exactIdx = -1
    prefixNum = ""
    idx = 0
    for each ch in m.liveTvChannels
        if type(ch) = "roAssociativeArray" then
            ' Channel numbers are stored as the integer chNo (1..N after the
            ' curated renumber), so coerce to text for prefix matching.
            rawNo = SafeGet(ch, "chNo", invalid)
            num = ""
            if rawNo <> invalid then num = rawNo.ToStr()
            if num <> "" then
                if num = entry then
                    exactIdx = idx
                    exit for
                end if
                if prefixNum = "" and Left(num, Len(entry)) = entry then
                    prefixNum = num
                end if
            end if
        end if
        idx = idx + 1
    end for
    if exactIdx >= 0 then
        m.liveTvNumEntry = ""
        ? "LIVETV num " + entry + " -> idx=" + exactIdx.ToStr()
        LiveTvJumpToIndex(exactIdx)
        return
    end if
    m.liveTvNumEntry = entry
    if prefixNum <> "" then
        LiveTvSetStatus("CH " + entry + "  (" + prefixNum + ")")
    else
        LiveTvSetStatus("CH " + entry)
    end if
end sub

' Jump the list to a channel index, or move the grid cursor there when the
' grid is the active view.
sub LiveTvJumpToIndex(idx as Integer)
    if idx < 0 or idx >= m.liveTvChannels.count() then return
    if m.liveTvZone = "grid" then
        if m.liveTvGridState = invalid then return
        LiveTvGridCenterOn(m.liveTvGridState, idx)
        ch = m.liveTvChannels[idx]
        LiveTvSetStatus(LiveTvChanNoText(ch) + "  " + SafeStr(ch, "title", ""))
        return
    end if
    LiveTvSelectChannel(idx, true)
    LiveTvFocusZone()
end sub

function LiveTvChanNoText(ch as Object) as String
    if type(ch) <> "roAssociativeArray" then return ""
    rawNo = SafeGet(ch, "chNo", invalid)
    if rawNo = invalid then return ""
    return rawNo.ToStr()
end function

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if m.liveTvClosed then return false
    ' Numeric channel entry, cable-box style: type a channel number in both
    ' the list and the grid. Checked before every other key so a digit is
    ' never swallowed by navigation.
    if LiveTvIsDigitKey(key) then
        LiveTvNumEntry(key)
        return true
    end if
    if m.liveTvNumEntry <> "" and LiveTvIsNavKey(key) then
        ' Any navigation cancels a half-typed number.
        m.liveTvNumEntry = ""
    end if
    ' INFO is the guide shortcut. It works from the channel list, from a
    ' genre list AND over fullscreen playback, which is the whole point: you
    ' are watching a channel, you want to see what else is on, and you should
    ' not have to leave the picture first. Pressing it again closes the grid
    ' and puts you back exactly where you were, including back on the video.
    if key = "info" then
        if m.liveTvZone = "grid" then
            LiveTvGridCloseView()
            prevZone = m.liveTvZoneBeforeGrid
            if prevZone = invalid or prevZone = "" or prevZone = "grid" then prevZone = "channels"
            m.liveTvZone = prevZone
            LiveTvFocusZone()
            if m.liveTvZone = "fullscreen" then
                LiveTvShowFsBanner()
            else
                LiveTvSetStatus("Up/Down surf  •  OK fullscreen  •  INFO grid  •  Back exit")
            end if
        else
            m.liveTvZoneBeforeGrid = m.liveTvZone
            ' INFO, not SELECT: nothing to swallow afterwards.
            LiveTvGridOpenView(false)
            ' OpenView refuses (and explains) when the lineup is empty, so only
            ' claim the grid zone if it actually came up.
            if m.liveTvGridOpen = true then
                m.liveTvZone = "grid"
            end if
        end if
        return true
    end if
    ' LIVE GRID owns the keyboard while it is up (BACK unwinds first).
    if m.liveTvZone = "grid" then
        if key = "back" then
            LiveTvGridCloseView()
            ' Restore the zone the grid was opened over, not a hardcoded
            ' "channels" - otherwise BACK from the grid drops you out of a
            ' genre list or off fullscreen playback.
            prevZone = m.liveTvZoneBeforeGrid
            if prevZone = invalid or prevZone = "" or prevZone = "grid" then prevZone = "channels"
            m.liveTvZone = prevZone
            LiveTvFocusZone()
            if m.liveTvZone = "fullscreen" then
                LiveTvShowFsBanner()
            else
                LiveTvSetStatus("Up/Down surf  •  OK fullscreen  •  INFO grid  •  Back exit")
            end if
            return true
        end if
        return LiveTvGridKey(key)
    end if
    if key = "back" then
        if m.liveTvZone = "fullscreen" then
            ? "LIVETV exit-key=back"
            LiveTvExitFullscreen()
            return true
        end if
        LiveTvClose()
        return true
    end if
    if key = "OK" then
        if m.liveTvZone = "fullscreen" then
            if m.liveTvIgnoreNextOk = true then
    m.liveTvIgnoreNextOk = false
    m.liveTvNumEntry = ""
                ? "LIVETV entering-OK consumed (no exit)"
                return true
            end if
            ? "LIVETV exit-key=OK"
            LiveTvExitFullscreen()
            return true
        end if
        return false
    end if
    if key = "up" then
        if m.liveTvZone = "fullscreen" then
            LiveTvZapStep(-1)
            return true
        end if
        return false
    end if
    if key = "down" then
        if m.liveTvZone = "fullscreen" then
            LiveTvZapStep(1)
            return true
        end if
        return false
    end if
    if key = "right" then
        if m.liveTvZone = "genres" then
            m.liveTvZone = "channels"
            LiveTvFocusZone()
            return true
        end if
        return false
    end if
    if key = "left" then
        if m.liveTvZone = "channels" then
            m.liveTvZone = "genres"
            LiveTvFocusZone()
            return true
        end if
        return false
    end if
    return false
end function

sub LiveTvClose()
    if m.liveTvClosed then return
    m.liveTvClosed = true
    if m.liveTvClockTimer <> invalid then m.liveTvClockTimer.control = "stop"
    if m.liveTvTuneTimer <> invalid then m.liveTvTuneTimer.control = "stop"
    if m.liveTvLoadTimer <> invalid then m.liveTvLoadTimer.control = "stop"
    LiveTvStopSurf()
    if m.liveTvTask <> invalid then
        m.liveTvTask.control = "stop"
        m.liveTvTask = invalid
    end if
    LiveTvStopResolveTask()
    LiveTvStopSudoResolveTask()
    LiveTvStopSudoLineupTask()
    LiveTvStopPremiumLineupTask()
    LiveTvHideFsBanner()
    if m.liveTvPreview <> invalid then m.liveTvPreview.control = "stop"
    if m.liveTvFsVideo <> invalid then
        m.liveTvFsVideo.control = "stop"
        m.liveTvFsVideo.unobserveField("state")
        m.liveTvFsVideo.content = invalid
        m.liveTvFsVideo.visible = false
    end if
    if m.liveTvFsDim <> invalid then m.liveTvFsDim.visible = false
    m.top.done = true
end sub
