sub init()
    m.title = m.top.findNode("title")
    m.subLabel = m.top.findNode("subLabel")
    m.episodesList = m.top.findNode("episodesList")
    m.cfg = ConfigLoad()

    m.episodesList.observeField("itemSelected", "OnEpisodeSelected")
    m.top.observeField("series", "OnSeasonSet")
    m.top.observeField("seasonNum", "OnSeasonSet")
    m.playback = invalid
end sub

sub OnSeasonSet()
    series = m.top.series
    seasonNum = m.top.seasonNum
    ' seasonNum defaults to -1 (see EpisodeScene.xml) so that picking
    ' TMDB season 0 ("Specials") still changes the field and fires this
    ' observer. The series field is set first and fires this too, so bail
    ' until a real season number has arrived.
    if seasonNum = invalid or seasonNum < 0 then
        return
    end if
    if series <> invalid then
        m.title.text = series.title + "   -   Season " + seasonNum.ToStr()
    else
        m.title.text = "Season " + seasonNum.ToStr()
    end if

    ShowEpisodesLoading()
    FetchEpisodes()
end sub

' Loading skeleton: one visible row keeps focus feedback alive while the
' episode fetch is in flight (an empty LabelList shows no focus at all).
sub ShowEpisodesLoading()
    if m.episodesList = invalid then return
    content = CreateObject("roSGNode", "ContentNode")
    nd = content.createChild("ContentNode")
    nd.title = "Loading episodes..."
    m.episodesList.content = content
    m.episodesList.setFocus(true)
end sub

sub FetchEpisodes()
    if m.top.series = invalid or SafeStr(m.top.series, "tmdbId", "") = "" then
        m.episodesList.content = CreateObject("roSGNode", "ContentNode")
        m.episodesList.setFocus(true)
        return
    end if
    url = TmdbTvEpisodesUrl(m.cfg, m.top.series.tmdbId, m.top.seasonNum)
    task = CreateObject("roSGNode", "ApiTask")
    task.url = url
    task.headers = TmdbHeaders(m.cfg.tmdbKey)
    task.observeField("raw", "OnEpisodesLoaded")
    m.episodesTask = task
    task.control = "run"
end sub

sub OnEpisodesLoaded(msg as Object)
    data = invalid
    if msg <> invalid then
        raw = msg.getData()
        if raw <> invalid and raw <> "" then
            data = JsonParseSafe(raw)
        end if
    end if
    content = CreateObject("roSGNode", "ContentNode")
    episodes = SafeGet(data, "episodes", [])
    noneFound = true
    if episodes <> invalid then
        if episodes.count() > 0 then noneFound = false
    end if
    if noneFound then
        nd = content.createChild("ContentNode")
        nd.title = "No episodes listed."
        m.episodesList.content = content
        m.episodesList.setFocus(true)
        return
    end if
    m.profiles = ProfilesLoad()
    pid = ProfilesGetActiveId(m.profiles)
    seriesId = ""
    if m.top.series <> invalid then
        seriesId = SafeStr(m.top.series, "tmdbId", "")
    end if
    for each e in episodes
        epNum = SafeStr(e, "episode_number", "0").toInt()
        epTitle = "Ep " + SafeStr(e, "episode_number", "0") + ": " + SafeStr(e, "name", "Untitled")
        if pid <> "" and seriesId <> "" then
            rk = { tmdbId: seriesId, mediaType: "tv", season: m.top.seasonNum.ToStr(), episode: epNum.ToStr() }
            r = ProfilesGetResume(m.profiles, pid, rk)
            if r <> invalid then
                epTitle = epTitle + "  •  " + ProfilesFormatTime(ProfilesInt(r, "p", 0))
            end if
        end if
        nd = content.createChild("ContentNode")
        nd.title = epTitle
        ' Custom fields must be declared with addField before assignment,
        ' else SceneGraph throws a runtime error (freezes the app).
        nd.addField("episode_number", "integer", false)
        nd.addField("name", "string", false)
        nd.episode_number = SafeStr(e, "episode_number", "0").toInt()
        nd.name = SafeStr(e, "name", "")
    end for
    m.episodesList.content = content
    if m.subLabel <> invalid then
        seasonNumNow = m.top.seasonNum
        if seasonNumNow <> invalid and seasonNumNow >= 0 then
            subText = "SEASON " + seasonNumNow.ToStr() + "  •  " + content.getChildCount().ToStr() + " EPISODES"
            m.subLabel.text = subText
        end if
    end if
    m.episodesList.setFocus(true)
end sub

sub OnEpisodeSelected()
    if m.episodesList.content = invalid then
        return
    end if
    item = m.episodesList.content.getChild(m.episodesList.itemSelected)
    if item = invalid then
        return
    end if
    ' hasField guard (audit finding): the "Loading episodes..." skeleton row
    ' never gets the custom field added, and reading a missing custom field
    ' throws on this firmware — an impatient OK during a slow fetch crashed
    ' the scene.
    if not item.hasField("episode_number") then
        return
    end if
    episodeNum = item.episode_number
    if episodeNum = invalid then
        return
    end if
    if episodeNum < 0 then
        return
    end if
    series = m.top.series
    if series = invalid then
        return
    end if
    seasonNum = m.top.seasonNum

    title = SafeStr(series, "title", "") + " S" + Pad2(seasonNum) + "E" + Pad2(episodeNum)
    epName = SafeStr(item, "name", "")
    if epName <> "" then
        title = title + " - " + epName
    end if

    rec = {
        mediaType: "tv",
        tmdbId: SafeStr(series, "tmdbId", ""),
        season: seasonNum.ToStr(),
        episode: episodeNum.ToStr(),
        title: title,
        poster: SafeStr(series, "poster", ""),
        backdrop: SafeStr(series, "backdrop", ""),
        year: SafeStr(series, "year", "")
    }

    if m.playback <> invalid then
        CleanupChild(m.playback)
        m.playback = invalid
    end if
    playback = CreateObject("roSGNode", "PlaybackScene")
    ' resumeRec first: the movie observer fires StartPlayback, which reads it.
    playback.resumeRec = rec
    playback.movie = rec
    playback.observeField("done", "OnPlaybackDone")
    m.playback = playback
    m.top.appendChild(playback)
    playback.setFocus(true)
end sub

sub OnPlaybackDone()
    CleanupChild(m.playback)
    m.playback = invalid
    m.episodesList.setFocus(true)
end sub

function Pad2(n as Integer) as String
    if n < 10 then
        return "0" + n.ToStr()
    end if
    return n.ToStr()
end function

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

function onKeyEvent(key as String, press as Boolean) as Boolean
    if press and key = "back" then
        if m.playback <> invalid then
            return true
        end if
        ' Stop the in-flight episodes fetch (audit finding): orphaned tasks
        ' run to completion and keep the detached scene alive.
        if m.episodesTask <> invalid then
            m.episodesTask.control = "stop"
            m.episodesTask = invalid
        end if
        m.top.done = true
        return true
    end if
    return false
end function