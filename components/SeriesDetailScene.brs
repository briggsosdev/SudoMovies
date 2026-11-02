sub init()
    m.bg = m.top.findNode("bg")
    m.backdrop = m.top.findNode("backdrop")
    m.title = m.top.findNode("title")
    m.titleShadow = m.top.findNode("titleShadow")
    m.meta = m.top.findNode("meta")
    m.overview = m.top.findNode("overview")
    m.seasonsList = m.top.findNode("seasonsList")
    m.backHint = m.top.findNode("backHint")
    m.toastTimer = m.top.findNode("toastTimer")
    m.cfg = ConfigLoad()
    m.profiles = ProfilesLoad()
    m.hintDefault = "* adds watchlist  •  INFO plays the trailer  •  OK opens season  •  BACK returns home"

    m.seasonsList.observeField("itemSelected", "OnSeasonSelected")
    m.top.observeField("series", "OnSeriesSet")
    if m.toastTimer <> invalid then
        m.toastTimer.observeField("fire", "OnToastDone")
    end if
    m.episodeScene = invalid
    m.seasonsTask = invalid
    m.trailerTask = invalid
    m.trailerScene = invalid
    if m.backHint <> invalid then m.backHint.text = m.hintDefault
end sub

' ------------------------------------------------------------------
' Trailer: same YoutubeTask -> TrailerScene path the movie details panel
' uses, kept local to this scene because Trailer.brs is written against
' HomeScene's m.detailsList / m.rows / ShowToast and cannot be included
' here. The lookup itself is shared - YoutubeTask only needs a tmdbId and
' a media type.
' ------------------------------------------------------------------
sub SeriesTrailerOpen()
    rec = m.series
    if rec = invalid then
        SeriesToast("Nothing to play a trailer for")
        return
    end if
    if SafeStr(rec, "tmdbId", "") = "" then
        SeriesToast("No trailer for this title")
        return
    end if
    SeriesTrailerCloseScene()
    SeriesTrailerStopTask()
    task = CreateObject("roSGNode", "YoutubeTask")
    if task = invalid then
        SeriesToast("Trailer is not available")
        return
    end if
    m.trailerTask = task
    task.observeField("status", "SeriesTrailerOnStatus")
    task.tmdbId = SafeStr(rec, "tmdbId", "")
    task.mediaType = "tv"
    task.title = SafeStr(rec, "title", "")
    if m.cfg <> invalid then
        task.tmdbKey = SafeStr(m.cfg, "tmdbKey", "")
    end if
    ? "SERIES trailer lookup tmdb=" + task.tmdbId
    SeriesToast("Looking up trailer...")
    task.control = "run"
end sub

' A result for an ABANDONED lookup must never open a player.
' NODE COMPARISON RULE: `=` on two nodes throws &h18 on this firmware -
' invalid-check first, then isSameNode().
sub SeriesTrailerOnStatus(evt as Object)
    src = invalid
    if evt <> invalid then src = evt.getRoSGNode()
    if src = invalid then return
    if m.trailerTask = invalid then return
    if not src.isSameNode(m.trailerTask) then return
    SeriesTrailerStopTask()
    st = src.status
    if st = invalid then st = 0
    vid = src.videoId
    if vid = invalid then vid = ""
    detail = ""
    if src.errorDetail <> invalid then detail = src.errorDetail
    if st <> 200 or vid = "" then
        ? "SERIES trailer miss status=" + st.ToStr() + " detail=" + detail
        if detail = "" then detail = "No trailer for this title."
        SeriesToast(detail)
        return
    end if
    SeriesTrailerOpenScene(vid, SafeStr(m.series, "title", ""))
end sub

sub SeriesTrailerOpenScene(videoIdIn as String, titleIn as String)
    if videoIdIn = invalid or videoIdIn = "" then
        SeriesToast("No trailer for this title.")
        return
    end if
    SeriesTrailerCloseScene()
    scene = CreateObject("roSGNode", "TrailerScene")
    if scene = invalid then
        SeriesToast("Trailer is not available")
        return
    end if
    scene.videoId = videoIdIn
    if titleIn <> invalid and titleIn <> "" then scene.titleText = titleIn
    scene.observeField("done", "SeriesTrailerDone")
    m.trailerScene = scene
    m.top.appendChild(scene)
    scene.setFocus(true)
end sub

sub SeriesTrailerDone()
    SeriesTrailerCloseScene()
    if m.seasonsList <> invalid then m.seasonsList.setFocus(true)
end sub

sub SeriesTrailerCloseScene()
    if m.trailerScene <> invalid then
        CleanupChild(m.trailerScene)
        m.trailerScene = invalid
    end if
end sub

sub SeriesTrailerStopTask()
    if m.trailerTask <> invalid then
        m.trailerTask.control = "stop"
        m.trailerTask = invalid
    end if
end sub

sub OnSeriesSet()
    series = m.top.series
    if series = invalid then return

    m.title.text = series.title
    if m.titleShadow <> invalid then
        m.titleShadow.text = series.title
    end if
    if series.overview <> "" and series.overview <> invalid then
        m.overview.text = series.overview
    else
        m.overview.text = "No overview available."
    end if
    if series.backdrop <> "" and series.backdrop <> invalid then
        m.backdrop.uri = series.backdrop
    end if

    meta = ""
    if series.year <> "" and series.year <> invalid then
        meta = series.year
    end if
    if series.rating <> "" and series.rating <> invalid then
        if meta <> "" then
            meta = meta + "   •   "
        end if
        meta = meta + "TMDB " + series.rating.ToStr()
    end if
    m.meta.text = meta

    ShowSeriesLoading()
    FetchSeasons()
end sub

' Loading skeleton: one visible row keeps focus feedback alive while the
' seasons fetch is in flight (an empty LabelList shows no focus at all).
sub ShowSeriesLoading()
    if m.seasonsList = invalid then return
    content = CreateObject("roSGNode", "ContentNode")
    nd = content.createChild("ContentNode")
    nd.title = "Loading seasons..."
    m.seasonsList.content = content
    m.seasonsList.setFocus(true)
end sub

sub FetchSeasons()
    url = TmdbTvSeasonsUrl(m.cfg, m.top.series.tmdbId)
    task = CreateObject("roSGNode", "ApiTask")
    task.url = url
    task.headers = TmdbHeaders(m.cfg.tmdbKey)
    task.observeField("raw", "OnSeasonsLoaded")
    m.seasonsTask = task
    task.control = "run"
end sub

sub OnSeasonsLoaded(msg as Object)
    data = invalid
    if msg <> invalid then
        raw = msg.getData()
        if raw <> invalid and raw <> "" then
            data = JsonParseSafe(raw)
        end if
    end if
    content = CreateObject("roSGNode", "ContentNode")
    seasons = SafeGet(data, "seasons", [])
    noneFound = true
    if seasons <> invalid then
        if seasons.count() > 0 then noneFound = false
    end if
    if noneFound then
        nd = content.createChild("ContentNode")
        nd.title = "No seasons listed."
    else
    seasonTotal = 0
    for each s in seasons
        seasonNumText = SafeStr(s, "season_number", "0")
        if seasonNumText <> "0" then
            seasonTotal = seasonTotal + 1
        end if
        nd = content.createChild("ContentNode")
        seasonLine = "Season " + seasonNumText
        epCountText = SafeStr(s, "episode_count", "")
        if epCountText <> "" and epCountText <> "0" then
            seasonLine = seasonLine + "  •  " + epCountText + " episodes"
        end if
        nd.title = seasonLine
        ' Custom fields must be declared with addField before assignment,
        ' else SceneGraph throws a runtime error (freezes the app).
        nd.addField("season_number", "integer", false)
        nd.season_number = SafeStr(s, "season_number", "0").toInt()
    end for
    if seasonTotal > 0 and m.meta <> invalid then
        cur = ""
        if m.meta.text <> invalid then cur = m.meta.text
        if cur <> "" then cur = cur + "   •   "
        m.meta.text = cur + seasonTotal.ToStr() + " Seasons"
    end if
    end if
    m.seasonsList.content = content
    m.seasonsList.setFocus(true)
end sub

sub OnSeasonSelected()
    if m.seasonsList.content = invalid then
        return
    end if
    item = m.seasonsList.content.getChild(m.seasonsList.itemSelected)
    if item = invalid then
        return
    end if
    ' hasField guard (audit finding): the "Loading seasons..." skeleton row
    ' never gets the custom field added, and reading a missing custom field
    ' throws on this firmware — an impatient OK during a slow fetch crashed
    ' the scene.
    if not item.hasField("season_number") then
        return
    end if
    seasonNum = item.season_number
    if seasonNum = invalid then
        return
    end if
    if seasonNum < 0 then
        return
    end if
    episodeScene = CreateObject("roSGNode", "EpisodeScene")
    episodeScene.series = m.top.series
    episodeScene.seasonNum = seasonNum
    episodeScene.observeField("done", "OnEpisodeSceneDone")
    m.episodeScene = episodeScene
    m.top.appendChild(episodeScene)
    episodeScene.setFocus(true)
end sub

sub OnEpisodeSceneDone()
    CleanupChild(m.episodeScene)
    m.episodeScene = invalid
    m.seasonsList.setFocus(true)
end sub

sub CleanupChild(node as Object)
    if node = invalid then
        return
    end if
    kids = m.top.getChildren(-1, 0)
    for each k in kids
        if k.isSameNode(node) then
            m.top.removeChild(node)
            exit for
        end if
    end for
end sub

' ------------------------------------------------------------------
' Watchlist (* key): TV shows previously had NO add-to-watchlist anywhere
' (user request + audit). Toggle mirrors HomeScene's movie-details option
' and the * quick-add on home tiles; the hint bar doubles as the toast.
' ------------------------------------------------------------------

sub SeriesToggleWatchlist()
    series = m.top.series
    if series = invalid then return
    pid = ProfilesGetActiveId(m.profiles)
    if pid = "" then
        SeriesToast("Pick a profile first (home • PROFILES)")
        return
    end if
    if SafeStr(series, "tmdbId", "") = "" then
        SeriesToast("Nothing to save for this title")
        return
    end if
    m.profiles = ProfilesLoad()
    nowIn = ProfilesWatchlistToggle(m.profiles, pid, series)
    PersistDrain()
    if nowIn then
        SeriesToast("Added to watchlist")
    else
        SeriesToast("Removed from watchlist")
    end if
end sub

' Transient hint-bar message: shows the text, restores the default hint
' after toastTimer (2s) fires.
sub SeriesToast(text as String)
    if m.backHint <> invalid then
        m.backHint.text = text
    end if
    if m.toastTimer <> invalid then
        m.toastTimer.control = "stop"
        m.toastTimer.control = "start"
    end if
end sub

sub OnToastDone()
    if m.backHint <> invalid then
        m.backHint.text = m.hintDefault
    end if
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if key = "back" then
        ' The trailer player is the topmost child, so BACK has to unwind it
        ' before the season list and before the scene itself.
        if m.trailerScene <> invalid then
            SeriesTrailerCloseScene()
            SeriesTrailerStopTask()
            if m.seasonsList <> invalid then m.seasonsList.setFocus(true)
            return true
        end if
        if m.episodeScene <> invalid then
            CleanupChild(m.episodeScene)
            m.episodeScene = invalid
            m.seasonsList.setFocus(true)
            return true
        end if
        ' Stop the in-flight seasons fetch (audit finding): orphaned tasks
        ' run to completion and keep the detached scene alive.
        if m.seasonsTask <> invalid then
            m.seasonsTask.control = "stop"
            m.seasonsTask = invalid
        end if
        ' Leaving the screen with a lookup still in flight would strand the
        ' task and let a late event open a player over the home screen.
        SeriesTrailerStopTask()
        SeriesTrailerCloseScene()
        m.top.done = true
        return true
    end if
    if key = "options" then
        if m.episodeScene <> invalid then return false
        SeriesToggleWatchlist()
        return true
    end if
    ' INFO is the trailer shortcut on the TV info screen. It is the same key
    ' the live grid uses on the Live TV screen, but these are different scenes
    ' so they never collide.
    if key = "info" then
        if m.episodeScene <> invalid then return false
        SeriesTrailerOpen()
        return true
    end if
    return false
end function