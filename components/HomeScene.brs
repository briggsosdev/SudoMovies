' Thin init wrapper (blind-console device): an exception anywhere in the
' boot chain previously killed the event loop silently — dimmed profile
' picker, dead remote, no diagnostics. Now every boot failure surfaces as
' a red on-screen banner naming the stage + message.
sub init()
    try
        HomeInitReal()
    catch e
        ShowFatalError("home init", e)
    end try
end sub

' Boot stage pill: a small red indicator top-left that names the last boot
' stage reached. Re-appended on every update so it stays above the startup
' picker's opaque dim. Removed when boot completes (BootStageDone). If the
' app ever dies mid-boot again, the pill that remains on screen IS the
' crash site.
sub BootStage(stage as String)
    if m.bootLabel = invalid then
        g = CreateObject("roSGNode", "Group")
        bg = CreateObject("roSGNode", "Rectangle")
        bg.color = "0xD42028FF"
        bg.translation = "[8,8]"
        bg.width = 480
        bg.height = 36
        lbl = CreateObject("roSGNode", "Label")
        lbl.font = "font:SmallSystemFont"
        lbl.color = "0xFFFFFFFF"
        lbl.translation = "[8,8]"
        lbl.width = 480
        lbl.height = 36
        lbl.vertAlign = "center"
        g.appendChild(bg)
        g.appendChild(lbl)
        m.bootLabel = lbl
        m.bootGroup = g
    end if
    m.bootLabel.text = stage
    m.top.removeChild(m.bootGroup)
    m.top.appendChild(m.bootGroup)
end sub

sub BootStageDone()
    if m.bootPickerDone = true and m.bootRowsDone = true and m.bootGroup <> invalid then
        m.top.removeChild(m.bootGroup)
        m.bootGroup = invalid
        m.bootLabel = invalid
    end if
end sub

' Permanent red banner (topmost at call time, so it reads over the picker
' dim). This is the app's only working debug channel on this TV.
sub ShowFatalError(where as String, e as Dynamic)
    txt = "APP ERROR - " + where + ": " + HomeErrorText(e)
    ? txt
    g = CreateObject("roSGNode", "Group")
    bg = CreateObject("roSGNode", "Rectangle")
    bg.color = "0x0B0E17FF"
    bg.translation = "[0,100]"
    bg.width = 1920
    bg.height = 260
    edge = CreateObject("roSGNode", "Rectangle")
    edge.color = "0xD42028FF"
    edge.translation = "[0,100]"
    edge.width = 1920
    edge.height = 6
    lbl = CreateObject("roSGNode", "Label")
    lbl.text = txt
    lbl.font = "font:MediumBoldSystemFont"
    lbl.color = "0xFFFFFFFF"
    lbl.translation = "[64,130]"
    lbl.width = 1792
    lbl.height = 200
    lbl.wrap = true
    lbl.vertAlign = "top"
    g.appendChild(bg)
    g.appendChild(edge)
    g.appendChild(lbl)
    m.top.appendChild(g)
    if m.statusLabel <> invalid then m.statusLabel.text = txt
end sub

sub HomeInitReal()
    m.c = AppConstants()
    m.cfg = ConfigLoad()
    m.rows = m.top.findNode("rows")
    m.statusLabel = m.top.findNode("statusLabel")
    m.heroGroup = m.top.findNode("heroGroup")
    m.heroBackdrop = m.top.findNode("heroBackdrop")
    m.heroTitle = m.top.findNode("heroTitle")
    m.heroTitleShadow = m.top.findNode("heroTitleShadow")
    m.heroMeta = m.top.findNode("heroMeta")
    m.heroOverview = m.top.findNode("heroOverview")
    m.heroKicker = m.top.findNode("heroKicker")
    m.heroPageLabel = m.top.findNode("heroPageLabel")
    m.heroBadgeBg = m.top.findNode("heroBadgeBg")
    m.heroBadgeLabel = m.top.findNode("heroBadgeLabel")

    verLabel = m.top.findNode("headerVersion")
    if verLabel <> invalid and m.c.version <> invalid then
        verLabel.text = "v" + m.c.version
    end if

    m.homeRowDefs = m.c.homeRows
    m.homeRowMovies = []
    m.rowRecords = []
    m.movieRecords = []
    m.focusedRow = 0
    m.focusedCol = 0
    m.inSearch = false
    m.query = ""
    m.searchResults = []
    m.searchPage = 0
    m.searchPages = 1
    m.searchLoading = false
    ' Search owns its OWN task ref. It used to run on the shared m.activeTask
    ' with the home-row loader; a home fetch landing mid-page stole that ref,
    ' the search response was dropped, and m.searchLoading stayed true
    ' forever (every later page then returned at the guard below).
    m.searchTask = invalid
    m.searchMoreIndex = -1
    m.selectedRec = invalid
    m.settingsStep = ""
    m.activeTask = invalid
    m.scrapeTask = invalid
    m.femboxTask = invalid
    m.vixTask = invalid
    m.femCandidates = []
    m.vixCandidates = []
    m.triedScrape = false
    m.triedFem = false
    m.triedVix = false
    m.femRetries = 0
    m.searchDialog = invalid
    m.settingsDialog = invalid
    m.settingsMenuGroup = invalid
    m.settingsMenuList = invalid
    m.seriesScene = invalid
    m.liveTvScene = invalid
    ' Trailer lifecycle (see Trailer.brs): the lookup task and the player
    ' scene are torn down on scene close, so neither outlives HomeScene.
    m.trailerTask = invalid
    m.trailerScene = invalid
    m.trailerTitle = ""
    m.detailsGroup = invalid
    m.detailsList = invalid
    m.detailsPoster = invalid
    m.detailsTitle = invalid
    m.detailsMeta = invalid
    m.detailsOverview = invalid
    m.detailsGenres = invalid
    m.progressGroup = invalid
    m.progressSmall = invalid
    m.pendingCandidates = invalid
    m.sourcePickerGroup = invalid
    m.sourceList = invalid
    m.playback = invalid
    m.profiles = ProfilesLoad()
    m.profilePickerGroup = invalid
    m.profileList = invalid
    m.profileItems = []
    m.profileDialog = invalid
    m.profileNameMode = ""
    m.profilePickerMode = ""
    m.pendingLaunch = invalid

    ' Row index map: CONTINUE/WATCHLIST get real indices only when they
    ' have content — empty personal rows are SKIPPED (no "Nothing here
    ' yet" placeholder), so the feed starts with real posters. TMDB rows
    ' follow from homeRowStart. Indices are assigned in BuildHomeRowsReal
    ' and the rail is rebuilt after (it reads them).
    m.homeRowStart = 0
    m.ROW_CONTINUE = -1
    m.ROW_WATCHLIST = -1
    m.lastFemError = ""
    m.watchlistHydrated = {}
    m.watchlistRowNode = invalid
    m.watchlistHydratePending = invalid
    m.wlTask = invalid
    m.hydTask = invalid
    m.hydrateTarget = invalid
    m.pendingSearchQuery = ""
    m.toastGroup = invalid
    m.toastLabel = invalid
    m.toastTimer = invalid
    m.toastAnim = invalid
    m.toastPhase = ""
    m.modalAnim = invalid
    m.modalAnimParent = invalid
    m.railList = m.top.findNode("railList")
    m.railBg = m.top.findNode("railBg")
    m.railItems = []
    m.genreGroup = invalid
    m.heroRecs = []
    m.heroIdx = 0
    m.heroRec = invalid
    m.heroTimer = invalid

    m.rows.observeField("rowItemFocused", "OnRowItemFocused")
    m.rows.observeField("rowItemSelected", "OnRowSelected")
    m.top.observeField("launchArgs", "OnLaunchArgs")
    m.autoPlay = false
    BuildRail()
    HeroTimerStart()

    m.homeNext = 0
    m.statusLabel.text = "Loading home..."
    m.bootPickerDone = false
    m.bootRowsDone = false
    BootStage("boot 1/4: home init")
    LoadHomeRows()
    BootStage("boot 2/4: rows loading")
    ShowProfilePicker("startup")
end sub

sub MaybeProcessLaunch()
    if m.pendingLaunch = invalid then return
    if m.profilePickerGroup <> invalid then return
    if ProfilesGetActiveId(m.profiles) = "" then return
    a = m.pendingLaunch
    m.pendingLaunch = invalid
    ProcessLaunchArgs(a)
end sub

sub OnLaunchArgs()
    a = m.top.launchArgs
    if a = invalid then return
    m.pendingLaunch = a
    MaybeProcessLaunch()
end sub

sub ProcessLaunchArgs(a as Object)
    if a = invalid then return
    id = ""
    ' OS passes lowercase contentid/mediatype; accept any case.
    ' https://developer.roku.com/dev/docs/implementing-deep-linking
    if a.contentId <> invalid then id = a.contentId.ToStr()
    if id = "" and a.contentid <> invalid then id = a.contentid.ToStr()
    if id = "" then return
    mt = "movie"
    if a.mediaType <> invalid and a.mediaType.ToStr() <> "" then mt = a.mediaType.ToStr()
    if mt = "movie" and a.mediatype <> invalid and a.mediatype.ToStr() <> "" then mt = a.mediatype.ToStr()
    ? "DEEPLINK id=" + id + " type=" + mt

    ' Search deep-link / voice entry (mediatype=search or a search term param):
    ' route into on-channel search. The existing Keypad live-results flow is
    ' untouched; this is a separate direct entry point.
    q = ""
    if a.searchTerm <> invalid then q = a.searchTerm.ToStr()
    if q = "" and a.searchterm <> invalid then q = a.searchterm.ToStr()
    if q = "" then
        mtl = LCase(mt)
        if mtl = "search" or mtl = "searchterm" then q = id
    end if
    if q <> "" then
        m.autoPlay = false
        m.pendingSearchQuery = q
        TryRunPendingSearch()
        return
    end if

    m.autoPlay = true
    rec = { tmdbId: id, mediaType: mt, title: "Deep link " + id, poster: "", backdrop: "", year: "", overview: "", rating: "", runtime: "", genres: "" }
    ShowDetails(rec)
    StartScrape()
end sub

' Run a pending search deep-link only once home rows are done loading, so it
' cannot collide with the home ApiTask (both share the render thread helpers).
sub TryRunPendingSearch()
    if m.pendingSearchQuery = "" then return
    if m.inSearch then return
    if m.homeNext < m.homeRowDefs.count() then return
    query = m.pendingSearchQuery
    m.pendingSearchQuery = ""
    RunSearch(query)
end sub

' ------------------------------------------------------------------
' Home rows (Netflix-style)
' ------------------------------------------------------------------

sub LoadHomeRows()
    m.homeRowMovies = []
    m.homeNext = 0
    m.inSearch = false
    m.movieRecords = []
    ' Leave search mode: a stale pagination index would make a normal home
    ' row look like the "MORE RESULTS" tile. The in-flight page is CANCELLED
    ' here, not left to time out: the row loader below takes the shared task
    ' slot, so a surviving search response used to be dropped as "not the
    ' current task" and left m.searchLoading stuck true for the whole session
    ' (paging then dead for every later search).
    SearchStopTask()
    m.searchLoading = false
    m.searchResults = []
    m.searchPage = 0
    m.searchPages = 1
    m.searchMoreIndex = -1
    FetchNextHomeRow()
end sub

sub FetchNextHomeRow()
    if m.homeNext >= m.homeRowDefs.count() then
        BuildHomeRows()
        return
    end if
    def = m.homeRowDefs[m.homeNext]
    ' Row sources:
    '   urban -> baked verified catalog (NO network: the old lineup endpoint
    '            brokensilenze.mom/api/channels 404s on every path, so it used
    '            to produce an "Unavailable" tile that never went away)
    '   anime -> reanime.to listing, parsed in OnHomeRowDone
    '   rest  -> TMDB discover JSON
    url = ""
    ' All home rows are now TMDB discover JSON.
    url = TmdbDiscoverUrl(m.cfg, def.id)
    totalRows = m.homeRowDefs.count()
    m.statusLabel.text = "Loading home... (" + (m.homeNext + 1).ToStr() + " of " + totalRows.ToStr() + ")"
    RunApiTask(url, TmdbHeaders(m.cfg.tmdbKey), "OnHomeRowDone")
end sub

' Row task done: identity-guarded (audit finding) — a late response from a
' task that is no longer the current ApiTask (e.g. a search overwrote
' m.activeTask) is dropped instead of being consumed as this row's data.
' NODE COMPARISON RULE (proven by runtime error &h18 on this firmware):
' `=`/`<>` on two roSGNode operands THROWS Type Mismatch — always compare
' against invalid first, then use isSameNode() for node identity.
sub OnHomeRowDone(msg as Object)
    task = msg.getRoSGNode()
    if task = invalid then return
    active = m.activeTask
    if active = invalid then return
    if not task.isSameNode(active) then return
    m.activeTask = invalid
    movies = []
    st = 0
    ' The current row def decides the parser: reanime.to listing for the
    ' anime row, TMDB discover JSON for everything else.
    curDef = invalid
    if m.homeNext < m.homeRowDefs.count() then curDef = m.homeRowDefs[m.homeNext]
    if task <> invalid then
        st = task.status
        if st = 200 then
            movies = TmdbParseMovies(task.raw)
        end if
    end if
    ? "HOME row " + m.homeNext.ToStr() + " status=" + st.ToStr() + " movies=" + movies.count().ToStr()
    m.homeRowMovies[m.homeNext] = movies
    m.homeNext = m.homeNext + 1
    FetchNextHomeRow()
end sub

sub BuildHomeRows()
    try
        BuildHomeRowsReal()
        ' Boot flag only while the boot pill is up (this also runs on
        ' RELOAD / search-exit later, long after boot completed).
        if m.bootGroup <> invalid then
            m.bootRowsDone = true
            BootStage("boot 4/4: rows built")
            BootStageDone()
        end if
    catch e
        ShowFatalError("home rows", e)
    end try
end sub

sub BuildHomeRowsReal()
    ' Don't let home rows clobber an active search feed (deep-link search or
    ' a live Keypad result still on screen).
    if m.inSearch then
        return
    end if
    content = CreateObject("roSGNode", "ContentNode")
    m.rowRecords = []
    ' Home rows are CONTENT only. Personal rows are added only when they
    ' have titles — empties are skipped outright (no single-tile
    ' placeholders), then the TMDB feed. Indices assigned as rows are
    ' created; rail rebuilt after since it reads these indices.
    idx = 0
    if AddContinueRow(content) > 0 then
        m.ROW_CONTINUE = idx
        idx = idx + 1
    else
        m.ROW_CONTINUE = -1
    end if
    if AddWatchlistRow(content) > 0 then
        m.ROW_WATCHLIST = idx
        idx = idx + 1
    else
        m.ROW_WATCHLIST = -1
        m.watchlistRowNode = invalid
    end if
    m.homeRowStart = idx
    totalTitles = 0
    ' Every def renders through this ONE loop, including urban and anime:
    ' their records arrive pre-shaped from UrbanCatalogRows() /
    ' UrbanParseAnimeBody(), so they need no special case here. The old
    ' second pass appended a placeholder "Urban Streams" row AFTER the loop
    ' and ignored the index it had computed, which produced two urban rows
    ' and shifted every rail jump target below it.
    for i = 0 to m.homeRowDefs.count() - 1
        def = m.homeRowDefs[i]
        movies = m.homeRowMovies[i]
        if movies = invalid then movies = []
        rowNode = content.createChild("ContentNode")
        head = HomeRowTitle(m.homeRowDefs[i].title, movies.count())
        if i = 0 and movies.count() > 0 then
            head = "TOP 10: " + UCase(m.homeRowDefs[i].title)
        end if
        rowNode.title = head
        if movies.count() = 0 then
            nd = rowNode.createChild("ContentNode")
            nd.HDPosterUrl = "pkg:/images/tile_empty_generic.png"
            nd.title = "Unavailable"
            nd.shortDescriptionLine1 = "Try Search or RELOAD"
            nd.addField("badge", "string", false)
            nd.badge = ""
        else
            totalTitles = totalTitles + movies.count()
            rankNum = 0
            for each rec in movies
                rankNum = rankNum + 1
                nd = rowNode.createChild("ContentNode")
                art = SafeStr(rec, "poster", "")
                if art = "" then art = "pkg:/images/poster_placeholder.png"
                nd.HDPosterUrl = art
                nd.title = SafeStr(rec, "title", "Untitled")
                nd.shortDescriptionLine1 = TileLine(rec)
                if i = 0 and rankNum <= 10 then
                    nd.addField("rank", "integer", false)
                    nd.rank = rankNum
                end if
                pct = HomeProgressPct(rec)
                if pct > 0 then
                    nd.addField("progress", "integer", false)
                    nd.progress = pct
                end if
                chipText = SafeStr(rec, "rating", "")
                if chipText <> "" then
                    nd.addField("chip", "string", false)
                    nd.chip = chipText
                end if
            end for
        end if
        m.rowRecords.Push(movies)
    end for
    m.rows.content = content
    SetRowItemSizes(content.getChildCount())
    HeroCollect()
    ' Row indices may have shifted (personal rows skipped when empty):
    ' rebuild the rail so HOME/MOVIES/SERIES/MY LIST/genre jumps land right.
    if m.railList <> invalid then BuildRail()
    if totalTitles = 0 then
        m.statusLabel.text = "Couldn't load anything. Check connection, then open RELOAD."
    else
        m.statusLabel.text = "OK opens details  •  PLAY plays featured  •  SEARCH finds titles"
    end if
    if not IsModalOpen() then
        m.rows.setFocus(true)
    end if
    TryRunPendingSearch()
end sub

' ------------------------------------------------------------------
' Hero / spotlight banner (Netflix-style featured title).
' Procedural shading over a TMDB w1280 backdrop the app already loads at
' runtime: zero bundled bytes. Timer rotation + focus tie-in share one
' instant setter (no opacity animation — instant and crisp per firmware).
' PLAY on the remote opens the featured title; OK keeps browsing rows.
' ------------------------------------------------------------------

sub HeroTimerStart()
    if m.heroTimer <> invalid then return
    clock = CreateObject("roSGNode", "Timer")
    clock.duration = 20.0
    clock.repeat = true
    clock.observeField("fire", "OnHeroTimerFire")
    m.heroTimer = clock
    m.top.appendChild(clock)
    clock.control = "start"
end sub

sub HeroUpdate(rec as Object)
    if rec = invalid then return
    if m.heroBackdrop = invalid then return
    ' Spotlight band: PORTRAIT poster thumb first (132x198),
    ' landscape backdrop only as a last resort (scaleToFit letterboxes it).
    art = SafeStr(rec, "poster", "")
    if art = "" then art = SafeStr(rec, "backdrop", "")
    if art <> "" then m.heroBackdrop.uri = art
    ttl = SafeStr(rec, "title", "")
    if ttl <> "" and m.heroTitle <> invalid then m.heroTitle.text = ttl
    if m.heroTitleShadow <> invalid then
        if ttl <> "" then
            m.heroTitleShadow.text = ttl
        else
            m.heroTitleShadow.text = ""
        end if
    end if
    if m.heroMeta <> invalid then m.heroMeta.text = BuildMetaLine(rec)
    ' Kicker line: Top-10 badge when the record carries a rank, a NEW tag
    ' for current-year titles (the premium "Recently Added" signal), else a
    ' quiet media-type tag. Mirrors "TOP 10 • #3 IN FILMS TODAY".
    if m.heroKicker <> invalid then
        rankNum = 0
        if rec.DoesExist("rank") then rankNum = Int(rec.rank)
        mt = UCase(SafeStr(rec, "mediaType", ""))
        kindWord = "FILMS"
        kindOne = "FILM"
        if mt = "TV" then
            kindWord = "SERIES"
            kindOne = "SERIES"
        end if
        if rankNum >= 1 and rankNum <= 10 then
            m.heroKicker.text = "TOP 10  •  #" + rankNum.ToStr() + " IN " + kindWord + " TODAY"
        else
            freshTag = ""
            ydt = CreateObject("roDateTime")
            if ydt <> invalid and SafeStr(rec, "year", "") = ydt.GetYear().ToStr() then freshTag = "NEW "
            m.heroKicker.text = freshTag + kindOne
        end if
    end if
    ov = SafeStr(rec, "overview", "")
    if ov = "" then ov = "No overview available for this title."
    if m.heroOverview <> invalid then m.heroOverview.text = ov
    m.heroRec = rec
end sub

sub HeroCollect()
    ' Two passes so the full-bleed hero favors LANDSCAPE art: first titles
    ' with a backdrop, then anything with art to fill up to 8 picks.
    picks = []
    if m.rowRecords <> invalid then
        for i = 0 to m.rowRecords.count() - 1
            recs = m.rowRecords[i]
            if recs <> invalid then
                for each rec in recs
                    if rec <> invalid and SafeStr(rec, "backdrop", "") <> "" and SafeStr(rec, "title", "") <> "" then
                        picks.Push(rec)
                        if picks.count() >= 8 then exit for
                    end if
                end for
            end if
            if picks.count() >= 8 then exit for
        end for
        if picks.count() < 8 then
            for i = 0 to m.rowRecords.count() - 1
                recs = m.rowRecords[i]
                if recs <> invalid then
                    for each rec in recs
                        if rec <> invalid and (SafeStr(rec, "poster", "") <> "" or SafeStr(rec, "backdrop", "") <> "") and SafeStr(rec, "title", "") <> "" then
                            dup = false
                            for each p in picks
                                if p <> invalid and SafeStr(p, "tmdbId", "") <> "" and SafeStr(p, "tmdbId", "") = SafeStr(rec, "tmdbId", "") then dup = true
                            end for
                            if not dup then picks.Push(rec)
                            if picks.count() >= 8 then exit for
                        end if
                    end for
                end if
                if picks.count() >= 8 then exit for
            end for
        end if
    end if
    m.heroRecs = picks
    m.heroIdx = 0
    if picks.count() > 0 then HeroUpdate(picks[0])
    HeroUpdatePage()
end sub

' Rotation affordance: "3 / 8" so the auto-rotating hero reads as a
' browsable spotlight, never a flickering banner. Static text only.
sub HeroUpdatePage()
    if m.heroPageLabel = invalid then return
    if m.heroRecs = invalid or m.heroRecs.count() = 0 then
        m.heroPageLabel.text = ""
        return
    end if
    m.heroPageLabel.text = (m.heroIdx + 1).ToStr() + " / " + m.heroRecs.count().ToStr()
end sub

sub HeroRotate()
    if m.heroRecs = invalid or m.heroRecs.count() = 0 then return
    m.heroIdx = m.heroIdx + 1
    if m.heroIdx >= m.heroRecs.count() then m.heroIdx = 0
    HeroUpdate(m.heroRecs[m.heroIdx])
    HeroUpdatePage()
end sub

sub OnHeroTimerFire()
    if IsModalOpen() then return
    if m.inSearch then return
    HeroRotate()
end sub

sub HeroFocusRefresh()
    if m.rowRecords = invalid then return
    if m.focusedRow < 0 or m.focusedRow >= m.rowRecords.count() then return
    recs = m.rowRecords[m.focusedRow]
    if recs = invalid or m.focusedCol < 0 or m.focusedCol >= recs.count() then return
    rec = recs[m.focusedCol]
    if rec = invalid then return
    if SafeStr(rec, "backdrop", "") = "" and SafeStr(rec, "poster", "") = "" then return
    cur = ""
    if m.heroRec <> invalid then cur = SafeStr(m.heroRec, "tmdbId", "")
    if cur <> SafeStr(rec, "tmdbId", "") then HeroUpdate(rec)
end sub

' ------------------------------------------------------------------
' Continue-watching row (built from the active profile's resume data)
' ------------------------------------------------------------------

function AddContinueRow(content as Object) as Integer
    recs = []
    pid = ProfilesGetActiveId(m.profiles)
    if pid <> "" then
        list = ProfilesResumeList(m.profiles, pid)
        for each entry in list
            e = entry.rec
            rec = {
                tmdbId: ProfilesStr(e, "t", ""),
                mediaType: ProfilesStr(e, "m", "movie"),
                season: ProfilesStr(e, "s", ""),
                episode: ProfilesStr(e, "e", ""),
                title: ProfilesStr(e, "ti", ""),
                poster: ProfilesStr(e, "po", ""),
                year: "",
                resume: e
            }
            if rec.title = "" then rec.title = "In progress"
            recs.Push(rec)
        end for
    end if
    ' Empty: skip the row entirely (no single-tile placeholder) so the
    ' home feed opens with real posters.
    if recs.count() = 0 then return 0
    rowNode = content.createChild("ContentNode")
    rowNode.title = HomeRowTitle("Continue Watching", recs.count())
    for each rec in recs
        nd = rowNode.createChild("ContentNode")
        if rec.poster <> "" and rec.poster <> invalid then
            nd.HDPosterUrl = rec.poster
        else
            nd.HDPosterUrl = "pkg:/images/poster_placeholder.png"
        end if
        nd.title = rec.title
        nd.shortDescriptionLine1 = ProfilesTileSuffix(rec)
        pct = HomeProgressPct(rec)
        if pct > 0 then
            nd.addField("progress", "integer", false)
            nd.progress = pct
        end if
    end for
    m.rowRecords.Push(recs)
    return recs.count()
end function

' ------------------------------------------------------------------
' My Watchlist row (lean store re-hydrated from TMDB)
' ------------------------------------------------------------------

function AddWatchlistRow(content as Object) as Integer
    ' Empty watchlist: skip the row entirely (no single-tile placeholder).
    pid = ProfilesGetActiveId(m.profiles)
    items = []
    if pid <> "" then items = ProfilesWatchlistGet(m.profiles, pid)
    if items = invalid or items.count() = 0 then
        m.watchlistRowNode = invalid
        return 0
    end if
    rowNode = content.createChild("ContentNode")
    rowNode.title = HomeRowTitle("My Watchlist", 0)
    m.watchlistRowNode = rowNode
    m.rowRecords.Push([])
    BuildWatchlistRowContent(rowNode, m.rowRecords.count() - 1)
    return items.count()
end function

' Safe indexed set on m.rowRecords (grows the array instead of a possible
' out-of-bounds index assignment when a row is built out of order).
sub SetRowRecord(idx as Integer, items as Object)
    if idx = invalid or idx < 0 then return
    while m.rowRecords.count() <= idx
        m.rowRecords.Push([])
    end while
    m.rowRecords[idx] = items
end sub

sub BuildWatchlistRowContent(rowNode as Object, recIdx as Integer)
    while rowNode <> invalid and rowNode.getChildCount() > 0
        rowNode.removeChildIndex(0)
    end while
    if rowNode = invalid then return
    pid = ProfilesGetActiveId(m.profiles)
    recs = []
    list = []
    if pid <> "" then
        list = ProfilesWatchlistGet(m.profiles, pid)
    end if
    if list.count() = 0 then
        nd = rowNode.createChild("ContentNode")
        nd.HDPosterUrl = "pkg:/images/tile_empty_watchlist.png"
        nd.title = "Nothing here yet"
        nd.shortDescriptionLine1 = "Details - Add to watchlist"
        nd.addField("badge", "string", false)
        nd.badge = ""
        SetRowRecord(recIdx, [])
        return
    end if
    rowNode.title = HomeRowTitle("My Watchlist", list.count())
    for each w in list
        if w <> invalid then
            key = ProfilesStr(w, "id", "") + "|" + ProfilesStr(w, "m", "movie")
            rec = m.watchlistHydrated[key]
            if rec = invalid then
                rec = {
                    tmdbId: ProfilesStr(w, "id", ""),
                    mediaType: ProfilesStr(w, "m", "movie"),
                    title: "Loading...",
                    poster: "",
                    year: ""
                }
            end if
            recs.Push(rec)
            nd = rowNode.createChild("ContentNode")
            if rec.poster <> "" and rec.poster <> invalid then
                nd.HDPosterUrl = rec.poster
            else
                nd.HDPosterUrl = "pkg:/images/poster_placeholder.png"
            end if
            nd.title = rec.title
            nd.shortDescriptionLine1 = SafeStr(rec, "year", "")
            chipText = SafeStr(rec, "rating", "")
            if chipText <> "" then
                nd.addField("chip", "string", false)
                nd.chip = chipText
            end if
        end if
    end for
    SetRowRecord(recIdx, recs)
    HydrateWatchlist()
end sub

' Fetch one missing watchlist title at a time (own task, does not collide with
' the home/search ApiTask) and refresh the row as each resolves.
sub HydrateWatchlist()
    if m.wlTask <> invalid then return
    pid = ProfilesGetActiveId(m.profiles)
    if pid = "" then return
    list = ProfilesWatchlistGet(m.profiles, pid)
    nextItem = invalid
    for each w in list
        if w <> invalid then
            key = ProfilesStr(w, "id", "") + "|" + ProfilesStr(w, "m", "movie")
            if m.watchlistHydrated[key] = invalid then
                nextItem = w
                exit for
            end if
        end if
    end for
    if nextItem = invalid then return
    url = TmdbDiscoverUrl(m.cfg, TmdbDetailPath(nextItem))
    if url = "" then return
    task = CreateObject("roSGNode", "ApiTask")
    task.url = url
    task.headers = TmdbHeaders(m.cfg.tmdbKey)
    task.observeField("raw", "OnWatchlistHydrated")
    m.watchlistHydratePending = nextItem
    m.wlTask = task
    task.control = "run"
end sub

sub OnWatchlistHydrated()
    task = m.wlTask
    m.wlTask = invalid
    w = m.watchlistHydratePending
    m.watchlistHydratePending = invalid
    if w <> invalid and task <> invalid then
        key = ProfilesStr(w, "id", "") + "|" + ProfilesStr(w, "m", "movie")
        if task.status = 200 and task.raw <> "" then
            full = TmdbParseDetail(task.raw, ProfilesStr(w, "m", "movie"))
            if full <> invalid then
                m.watchlistHydrated[key] = full
                ' Rebuild only on success (audit finding): a permanently
                ' unresolvable id used to refetch forever, tearing down the
                ' row (and its focus cursor) on every cycle.
                if m.watchlistRowNode <> invalid then
                    BuildWatchlistRowContent(m.watchlistRowNode, m.ROW_WATCHLIST)
                end if
            end if
        else
            ' Negative cache (audit finding): one failed hydrate caches the
            ' lean record so the loop cannot refetch a dead id forever. The
            ' lean tile still opens details (the details page fetches TMDB
            ' fresh by id); it just shows no poster.
            m.watchlistHydrated[key] = {
                tmdbId: ProfilesStr(w, "id", ""),
                mediaType: ProfilesStr(w, "m", "movie"),
                title: ProfilesStr(w, "t", ProfilesStr(w, "id", "Title")),
                poster: "", backdrop: "", year: "", overview: "",
                rating: "", runtime: "", genres: ""
            }
        end if
    end if
    HydrateWatchlist()
end sub

sub SetRowItemSizes(rowCount as Integer)
    try
        SetRowItemSizesReal(rowCount)
    catch e
        ShowFatalError("row sizes", e)
    end try
end sub

sub SetRowItemSizesReal(rowCount as Integer)
    ' RowList geometry: XML itemSize [1696,392] is the FULL ROW size, and
    ' these per-row arrays tile 224px posters ~7 per row with a 392px
    ' row height. (An xml-only experiment collapsed the layout and was
    ' reverted — the arrays stay.)
    ? "ROWS geometry rows=" + rowCount.ToStr() + " tile=224x336 row=1696x392"
    if rowCount <= 0 then return
    sizes = []
    heights = []
    spacings = []
    labelOffsets = []
    for i = 0 to rowCount - 1
        recs = invalid
        if m.rowRecords <> invalid and i < m.rowRecords.count() then
            recs = m.rowRecords[i]
        end if
        if recs <> invalid and type(recs) = "roArray" and recs.count() > 0 then
            ' Float literals: rowItemSize/rowHeights are vector2d/float
            ' arrays — integer pairs risk a type-mismatch throw on this
            ' firmware, which would skip the whole block.
            sizes.Push([224.0, 336.0])
            heights.Push(392.0)
        else
            sizes.Push([224.0, 140.0])
            heights.Push(196.0)
        end if
        spacings.Push([16.0, 0.0])
        labelOffsets.Push([48.0, 16.0])
    end for
    ' All four assignments guarded together: a firmware refusal skips the
    ' rest and falls back to the XML geometry (identical values) instead of
    ' ever raising the red "row sizes" banner. rowItemSpacing/rowLabelOffset
    ' take per-row arrays (they reject single "[x,y]" strings in markup).
    try
        m.rows.rowItemSize = sizes
        m.rows.rowHeights = heights
        m.rows.rowItemSpacing = spacings
        m.rows.rowLabelOffset = labelOffsets
    catch e
        ? "ROWS geometry arrays refused (XML geometry fallback active): " + HomeErrorText(e)
    end try
end sub

sub AddSpecialRow(content as Object, text as String, art as String, badge as String)
    rowNode = content.createChild("ContentNode")
    rowNode.title = HomeRowTitle(text, 0)
    nd = rowNode.createChild("ContentNode")
    nd.HDPosterUrl = art
    nd.title = text
    nd.shortDescriptionLine1 = ""
    ' "badge" is read by MovieGridItem: a non-empty value swaps the PLAY cue
    ' for this action text; an empty value hides the cue entirely.
    nd.addField("badge", "string", false)
    nd.badge = badge
    m.rowRecords.Push([])
end sub

sub AddProfilesRow(content as Object)
    nm = ProfilesGetActiveName(m.profiles)
    rowTitle = "Profiles"
    if nm <> "" then
        rowTitle = "Profiles  •  " + nm
    end if
    rowNode = content.createChild("ContentNode")
    rowNode.title = HomeRowTitle(rowTitle, 0)
    nd = rowNode.createChild("ContentNode")
    nd.HDPosterUrl = "pkg:/images/tile_profiles.png"
    nd.title = "PROFILES"
    if ProfilesGetActiveId(m.profiles) <> "" then
        nd.shortDescriptionLine1 = nm
    else
        nd.shortDescriptionLine1 = "Switch user"
    end if
    nd.addField("badge", "string", false)
    nd.badge = "SWITCH"
    m.rowRecords.Push([])
end sub

' Cheap in-progress indicator reusing the tile's year line (no row restructure).
function ProfilesTileSuffix(rec as Object) as String
    if m.profiles = invalid then return ""
    pid = ProfilesGetActiveId(m.profiles)
    if pid = "" then return ""
    if rec = invalid then return ""
    r = ProfilesGetResume(m.profiles, pid, rec)
    if r <> invalid then
        p = ProfilesInt(r, "p", 0)
        d = ProfilesInt(r, "d", 0)
        if d > 0 then
            pct = Int(p * 100 / d)
            return "  •  " + pct.ToStr() + "%"
        end if
        return "  •  " + ProfilesFormatTime(p)
    end if
    if SafeStr(rec, "mediaType", "") = "tv" and SafeStr(rec, "tmdbId", "") <> "" then
        if ProfilesSeriesHasResume(m.profiles, pid, "tv", rec.tmdbId) then
            return "  •  In progress"
        end if
    end if
    return ""
end function

' Refresh tile year lines in place (no focus change, no network).
sub RefreshProgressIndicators()
    if m.rows = invalid or m.rows.content = invalid then return
    if m.profiles = invalid then return
    if ProfilesGetActiveId(m.profiles) = "" then return
    content = m.rows.content
    for i = 0 to content.getChildCount() - 1
        if i >= m.rowRecords.count() then exit for
        recs = m.rowRecords[i]
        if recs <> invalid and recs.count() > 0 then
            rowNode = content.getChild(i)
            if rowNode <> invalid then
                for j = 0 to recs.count() - 1
                    if j >= rowNode.getChildCount() then exit for
                    tile = rowNode.getChild(j)
                    rec = recs[j]
                    if tile <> invalid and rec <> invalid then
                        tile.shortDescriptionLine1 = TileLine(rec)
                    end if
                end for
            end if
        end if
    end for
end sub

sub OnRowItemFocused(msg as Object)
    d = msg.getData()
    if d <> invalid and type(d) = "roArray" and d.count() >= 2 then
        m.focusedRow = d[0]
        m.focusedCol = d[1]
        ' Landing on the pagination tile pulls the next page in, so holding
        ' RIGHT keeps loading results with no extra key.
        if m.inSearch and m.searchMoreIndex >= 0 and d[1] >= m.searchMoreIndex then
            SearchFetchPage(m.searchPage + 1)
        end if
        HeroFocusRefresh()
        UpdateHomeHint()
    end if
end sub

' Persistent zero-dead-end hint: every home row states its next action so the
' user never wonders "what now". Only rewrites the idle hint, never an active
' loading or error line.
sub UpdateHomeHint()
    if m.statusLabel = invalid then return
    if m.homeNext < m.homeRowDefs.count() then return
    cur = m.statusLabel.text
    if cur = invalid then cur = ""
    if Instr(1, cur, "Loading") = 1 then return
    if Instr(1, cur, "Searching") = 1 then return
    if Instr(1, cur, "Couldn't") = 1 then return
    if Instr(1, cur, "No ") = 1 then return
    if Instr(1, cur, "Search failed") = 1 then return
    if Instr(1, cur, "Fetch cancelled") = 1 then return
    if Instr(1, cur, "Profile:") = 1 then return
    if Instr(1, cur, "Refreshing") = 1 then return
    row = m.focusedRow
    if m.inSearch then
        m.statusLabel.text = SearchResultsHint(m.movieRecords.count())
        return
    end if
    if row = m.ROW_CONTINUE then
        m.statusLabel.text = "OK resumes where you left off  •  BACK is always safe"
    else if row = m.ROW_WATCHLIST then
        m.statusLabel.text = "OK opens your saved titles  •  Add more from details"
    else
        m.statusLabel.text = "OK opens details  •  PLAY plays featured  •  SEARCH finds titles"
    end if
end sub

' ------------------------------------------------------------------
' Left rail: full section menu in premium order — Search, Home, Movies,
' Series, My List, Live TV, Genres, Profiles, Settings. Jump targets are
' computed from the row defs at build time (first movie def, first tv def),
' so the rail never depends on feed content or hardcoded offsets. Genres is
' ONE entry: it opens GenreBrowser, which carries every genre as a tab plus
' paging inside that single component, so the old "one rail item per genre,
' capped at 2" hack is gone and the rail fits with room to spare.
' Entered with LEFT at rows col 0, exited with RIGHT or BACK.
' ------------------------------------------------------------------

sub BuildRail()
    if m.railList = invalid then return
    items = []
    items.Push({ label: "SEARCH", action: "search", row: -1 })
    items.Push({ label: "HOME", action: "jump", row: m.homeRowStart })
    ' MOVIES and SERIES were never separate scenes - they only jumped the
    ' home rows to the first movie/tv row, and both feeds are already on the
    ' home screen. Removed so the rail is just real destinations.
    items.Push({ label: "MY LIST", action: "jump", row: MyListRailRow() })
    items.Push({ label: "LIVE TV", action: "livetv", row: -1 })
    ' ONE genre entry. It used to emit a rail item per discover/* def with a
    ' "GENRES cap at 2 so the rail fits" limit, each launching its own
    ' full-screen scene. GenreBrowser holds every genre as a tab with paging
    ' inside one component, so a single entry covers all of them.
    items.Push({ label: "GENRES", action: "genre", row: m.homeRowStart, genreId: "", genreTitle: "Genres" })
    items.Push({ label: "PROFILES", action: "profiles", row: -1 })
    items.Push({ label: "SETTINGS", action: "settings", row: -1 })
    m.railItems = items
    content = CreateObject("roSGNode", "ContentNode")
    for each it in items
        nd = content.createChild("ContentNode")
        nd.title = it.label
    end for
    m.railList.content = content
    m.railList.numRows = items.count()
    if m.railBg <> invalid then
        m.railBg.height = items.count() * 44 + 8
    end if
    ' The rail node is XML-persistent but this rebuild runs at init AND every
    ' row rebuild: without unobserving first, each rebuild stacked another
    ' itemSelected callback (one OK fired OnRailSelected Nx). Re-observing
    ' one node is idempotent only after unobserveField.
    m.railList.unobserveField("itemSelected")
    m.railList.observeField("itemSelected", "OnRailSelected")
end sub

sub OnRailSelected(msg as Object)
    if m.railList = invalid then return
    index = m.railList.itemSelected
    if index = invalid or m.railItems = invalid or index < 0 or index >= m.railItems.count() then
        if m.rows <> invalid then m.rows.setFocus(true)
        return
    end if
    item = m.railItems[index]
    ? "RAIL picked label=" + SafeStr(item, "label", "?")
    action = SafeStr(item, "action", "")
    if action = "search" then
        ShowSearchDialog()
    else if action = "livetv" then
        ShowLiveTv()
    else if action = "profiles" then
        ShowProfilePicker("manage")
    else if action = "settings" then
        ShowSettingsMenu()
    else if action = "genre" then
        ShowGenreScreen(SafeStr(item, "genreId", ""), SafeStr(item, "genreTitle", "Genre"))
    else if action = "jump" then
        RailJumpRow(HomeInt(item, "row", m.homeRowStart))
    else
        if m.rows <> invalid then m.rows.setFocus(true)
    end if
end sub

' MY LIST rail target: the watchlist row when it exists, else the first
' content row (RailJumpRow clamps negatives to 0 the same way).
function MyListRailRow() as Integer
    if m.ROW_WATCHLIST <> invalid and m.ROW_WATCHLIST >= 0 then return m.ROW_WATCHLIST
    if m.homeRowStart <> invalid and m.homeRowStart > 0 then return m.homeRowStart
    return 0
end function

' Safe integer read off a rail item AA (audit habit: never trust a field).
function HomeInt(obj as Object, key as String, fallback as Integer) as Integer
    if obj = invalid then return fallback
    if not obj.DoesExist(key) then return fallback
    v = obj[key]
    if v = invalid then return fallback
    t = type(v)
    if t = "Integer" or t = "roInt" then return v
    if t = "Float" or t = "roFloat" or t = "Double" or t = "roDouble" then return Int(v)
    return fallback
end function

sub RailJumpRow(row as Integer)
    if m.inSearch then
        m.statusLabel.text = ""
        LoadHomeRows()
        return
    end if
    if m.rows = invalid then return
    if row < 0 then row = 0
    m.rows.jumpToRowItem = [row, 0]
    m.rows.setFocus(true)
end sub

' Extract the numeric TMDB genre id from a discover def id
' ("discover/movie?with_genres=28" -> "28"). GenreBrowser's tab table uses
' the same `with_genres=NN` convention, so this stays the reference for how a
' def id maps to a genre id.
function GenreIdFromDef(idStr as String) as String
    if idStr = invalid or idStr = "" then return ""
    tag = "with_genres="
    p = Instr(1, idStr, tag)
    if p < 1 then return ""
    rest = Mid(idStr, p + Len(tag))
    out = ""
    for i = 1 to rest.Len()
        ch = rest.Mid(i - 1, 1)
        if ch >= "0" and ch <= "9" then
            out = out + ch
        else
            exit for
        end if
    end for
    return out
end function

' ------------------------------------------------------------------
' Genre browse: ONE full-screen genre component (GenreBrowser) holding
' every genre as a tab plus a paged poster grid, opened from the single
' GENRES rail entry. GenreBrowser runs its own ApiTask and guards the
' response by node identity, so it can never collide with the shared
' home-row loader.
' ------------------------------------------------------------------

sub ShowGenreScreen(genreId as String, title as String)
    if m.genreGroup <> invalid then
        CleanupChild(m.genreGroup)
        m.genreGroup = invalid
    end if
    scene = CreateObject("roSGNode", "GenreBrowser")
    if scene = invalid then
        m.statusLabel.text = "Genres are not available in this build."
        return
    end if
    ' Assign BEFORE flipping "start": GenreBrowser loads on the start flag,
    ' not from its own init, so the configured TMDB key is in place before
    ' the first discover call is built.
    if genreId <> invalid then scene.genreId = genreId
    if title <> invalid then scene.genreTitle = title
    if m.cfg <> invalid then scene.tmdbKey = m.cfg.tmdbKey
    scene.observeField("picked", "OnGenreScenePicked")
    scene.observeField("done", "OnGenreSceneDone")
    m.genreGroup = scene
    m.top.appendChild(scene)
    ? "GENRE browser open"
    scene.setFocus(true)
    ' start last: it is what kicks the first tab fetch.
    scene.start = true
end sub

sub OnGenreScenePicked()
    scene = m.genreGroup
    rec = invalid
    if scene <> invalid and scene.picked <> invalid then
        rec = scene.picked
    end if
    CloseGenreScreen()
    if rec = invalid then
        m.rows.setFocus(true)
        return
    end if
    if SafeStr(rec, "mediaType", "movie") = "tv" then
        ShowSeriesDetails(rec)
    else
        ShowDetails(rec)
    end if
end sub

sub OnGenreSceneDone()
    CloseGenreScreen()
    if m.rows <> invalid then m.rows.setFocus(true)
end sub

sub CloseGenreScreen()
    if m.genreGroup <> invalid then
        CleanupChild(m.genreGroup)
        m.genreGroup = invalid
    end if
end sub

function RailHasFocus() as Boolean
    if m.railList = invalid then return false
    return m.railList.hasFocus()
end function

sub OnRowSelected(msg as Object)
    row = m.focusedRow
    col = m.focusedCol
    if msg <> invalid then
        d = msg.getData()
        if d <> invalid and type(d) = "roArray" and d.count() >= 2 then
            row = d[0]
            col = d[1]
            m.focusedRow = row
            m.focusedCol = col
        end if
    end if
    ? "ROWSEL row=" + row.ToStr() + " col=" + col.ToStr() + " inSearch=" + m.inSearch.ToStr()
    if m.inSearch then
        if col >= 0 and col = m.searchMoreIndex then
            ' OK on the pagination tile loads more instead of opening nothing.
            SearchFetchPage(m.searchPage + 1)
        else if row = 0 and col < m.movieRecords.count() then
            rec = m.movieRecords[col]
            if rec.mediaType = "tv" then
                ShowSeriesDetails(rec)
            else
                ShowDetails(rec)
            end if
        end if
        return
    end if
    if row = m.ROW_CONTINUE or row = m.ROW_WATCHLIST then
        OpenContinueWatchingFromRow(row, col)
    else if row >= m.homeRowStart then
        if row < m.rowRecords.count() then
            recs = m.rowRecords[row]
            ' col guard also rejects col < 0 (cursor can transiently be -1
            ' right after a row rebuild).
            if recs <> invalid and col >= 0 and col < recs.count() then
                rec = recs[col]
                if rec = invalid then return
                ' Non-TMDB sources must never enter the TMDB details flow:
                ' reanime tiles have no tmdbId (ShowDetails would fetch the
                ' wrong title) and urban tiles resolve through the embed
                ' providers instead.
                src = SafeStr(rec, "source", "")
                if SafeStr(rec, "mediaType", "movie") = "tv" then
                    ShowSeriesDetails(rec)
                else
                    ShowDetails(rec)
                end if
            end if
        end if
    end if
end sub

' Hydrate a lean continue-watching / watchlist record from TMDB, then open it.
' ------------------------------------------------------------------

sub OpenContinueWatchingFromRow(row as Integer, col as Integer)
    if row >= m.rowRecords.count() then return
    recs = m.rowRecords[row]
    if recs = invalid or col < 0 or col >= recs.count() then return
    OpenContinueWatching(recs[col])
end sub

sub OpenContinueWatching(rec as Object)
    if rec = invalid then return
    m.hydrateTarget = rec
    url = TmdbDiscoverUrl(m.cfg, TmdbDetailPath(rec))
    if url = "" then
        m.selectedRec = rec
        if SafeStr(rec, "mediaType", "") = "tv" then
            ShowSeriesDetails(rec)
        else
            ShowDetails(rec)
        end if
        return
    end if
    task = CreateObject("roSGNode", "ApiTask")
    task.url = url
    task.headers = TmdbHeaders(m.cfg.tmdbKey)
    task.observeField("raw", "OnHydrateForOpen")
    m.hydTask = task
    task.control = "run"
end sub

sub OnHydrateForOpen()
    task = m.hydTask
    m.hydTask = invalid
    rec = m.hydrateTarget
    m.hydrateTarget = invalid
    if rec = invalid then return
    full = invalid
    if task <> invalid and task.status = 200 and task.raw <> "" then
        full = TmdbParseDetail(task.raw, SafeStr(rec, "mediaType", "movie"))
    end if
    if full = invalid then
        full = {
            tmdbId: SafeStr(rec, "tmdbId", ""),
            mediaType: SafeStr(rec, "mediaType", "movie"),
            title: SafeStr(rec, "title", ""),
            year: "",
            poster: SafeStr(rec, "poster", ""),
            backdrop: "",
            overview: "",
            rating: "",
            runtime: "",
            genres: ""
        }
        full.season = SafeStr(rec, "season", "")
        full.episode = SafeStr(rec, "episode", "")
    end if
    if SafeStr(full, "tmdbId", "") = "" then full.tmdbId = SafeStr(rec, "tmdbId", "")
    if SafeStr(full, "mediaType", "") = "" then full.mediaType = SafeStr(rec, "mediaType", "movie")
    m.selectedRec = full
    if SafeStr(full, "mediaType", "") = "tv" then
        ShowSeriesDetails(full)
    else
        ShowDetails(full)
    end if
end sub

sub ShowResults(movies as Object, resetFocus = true as Boolean)
    m.movieRecords = movies
    ' CURSOR: assigning m.rows.content resets the RowList focus cursor to
    ' [0,0], so appending a page used to throw the user back to the first
    ' tile — paging worked but was unusable past page 1. Remember where they
    ' were and re-aim after the swap with jumpToRowItem, the same cursor API
    ' RailJumpRow already uses.
    keepCol = m.focusedCol
    firstTitle = ""
    if movies.count() > 0 and movies[0].title <> invalid then
        firstTitle = movies[0].title
    end if
    ? "RESULTS count=" + movies.count().ToStr() + " first=" + firstTitle
    content = CreateObject("roSGNode", "ContentNode")
    rowNode = content.createChild("ContentNode")
    rowNode.title = HomeRowTitle("Results (" + movies.count().ToStr() + ")  -  " + Chr(34) + m.query + Chr(34), movies.count())
    for each rec in movies
        nd = rowNode.createChild("ContentNode")
        nd.HDPosterUrl = rec.poster
        nd.title = rec.title
        nd.shortDescriptionLine1 = SearchTileLine(rec)
        chipText = SafeStr(rec, "rating", "")
        if chipText <> "" then
            nd.addField("chip", "string", false)
            nd.chip = chipText
        end if
    end for
    ' Pagination tile: a real, visible next step instead of a silent dead end
    ' at the end of the list. MovieGridItem renders it with the placeholder
    ' poster and a badge, so it costs no new art.
    m.searchMoreIndex = -1
    if m.inSearch and m.searchPage < m.searchPages then
        more = rowNode.createChild("ContentNode")
        more.HDPosterUrl = "pkg:/images/poster_placeholder.png"
        more.title = "MORE RESULTS"
        nextPage = m.searchPage + 1
        more.shortDescriptionLine1 = "Page " + nextPage.ToStr() + " of " + m.searchPages.ToStr()
        more.addField("badge", "string", false)
        more.badge = Chr(9654)
        m.searchMoreIndex = movies.count()
    end if
    m.inSearch = true
    m.rows.content = content
    SetRowItemSizes(1)
    if resetFocus then
        for each rec in movies
            if rec <> invalid and SafeStr(rec, "backdrop", "") <> "" then
                HeroUpdate(rec)
                exit for
            end if
        end for
    end if
    m.focusedRow = 0
    if resetFocus then
        m.focusedCol = 0
        m.rows.setFocus(true)
    else
        ' Clamp to the new row length (the last poster, or the MORE tile when
        ' it is still there) so a stale column from a shorter list can never
        ' aim the cursor at a tile that no longer exists.
        lastCol = movies.count() - 1
        if m.searchMoreIndex >= 0 then lastCol = m.searchMoreIndex
        if keepCol > lastCol then keepCol = lastCol
        if keepCol < 0 then keepCol = 0
        m.focusedCol = keepCol
        m.rows.jumpToRowItem = [0, keepCol]
        m.rows.setFocus(true)
    end if
    m.statusLabel.text = SearchResultsHint(movies.count())
end sub

' One honest status line for a paged result list: what you have, whether more
' exist, and how to get them.
function SearchResultsHint(total as Integer) as String
    s = total.ToStr() + " titles"
    if m.searchPage > 1 then
        s = s + "  •  page " + m.searchPage.ToStr() + " of " + m.searchPages.ToStr()
    end if
    if m.searchMoreIndex >= 0 then
        s = s + "  •  RIGHT for more  •  OK opens details"
    else
        s = s + "  •  OK opens details  •  BACK goes home"
    end if
    return s
end function

' Scannable 10-foot tile line: year plus rating plus media badge so movies
' and shows read instantly apart. Strings only, no new art, zero bundle cost.
function SearchTileLine(rec as Object) as String
    yr = SafeStr(rec, "year", "")
    mt = UCase(SafeStr(rec, "mediaType", ""))
    rating = SafeStr(rec, "rating", "")
    line = yr
    if rating <> "" then
        if line <> "" then line = line + "  •  "
        line = line + rating + "/10"
    end if
    if mt <> "" then
        if line <> "" then line = line + "  •  "
        line = line + mt
    end if
    return line
end function

' Empty search is still a guided screen, never a dead end: one explained tile
' keeps focus alive plus an explicit next-action hint.
sub ShowEmptyResults()
    m.movieRecords = []
    content = CreateObject("roSGNode", "ContentNode")
    rowNode = content.createChild("ContentNode")
    rowNode.title = "RESULTS (0)  -  " + Chr(34) + m.query + Chr(34)
    nd = rowNode.createChild("ContentNode")
    nd.HDPosterUrl = "pkg:/images/tile_search_empty.png"
    nd.title = "No matches"
    nd.shortDescriptionLine1 = "Try another spelling"
    nd.addField("badge", "string", false)
    nd.badge = ""
    m.inSearch = true
    m.rows.content = content
    SetRowItemSizes(1)
    m.focusedRow = 0
    m.focusedCol = 0
    m.rows.setFocus(true)
    m.statusLabel.text = "No matches for " + Chr(34) + m.query + Chr(34) + "  •  BACK home  •  SEARCH tries again"
end sub

' ------------------------------------------------------------------
' Search (virtual keyboard for the D-pad remote)
' ------------------------------------------------------------------

sub ShowSearchDialog()
    if m.searchDialog <> invalid then
        return
    end if
    dialog = CreateObject("roSGNode", "Keypad")
    dialog.title = "Search movies and shows"
    dialog.message = "Type to see live results. RIGHT opens the poster grid, OK picks a title, DONE lists everything. CANCEL goes back."
    dialog.charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    dialog.searchMode = true
    dialog.tmdbKey = m.cfg.tmdbKey
    dialog.observeField("wasAccepted", "OnSearchAccepted")
    dialog.observeField("wasPicked", "OnSearchPicked")
    dialog.observeField("wasCancelled", "OnSearchCancelled")
    m.searchDialog = dialog
    m.top.appendChild(dialog)
    grid = dialog.findNode("keysGrid")
    if grid <> invalid then
        grid.setFocus(true)
    else
        dialog.setFocus(true)
    end if
    ? "KEYPAD search opened"
end sub

sub OnSearchAccepted(msg as Object)
    dialog = m.searchDialog
    query = ""
    if dialog <> invalid then
        query = dialog.text
        ' Keypad.text has no default and stays invalid until a key is typed;
        ' DONE on empty text would otherwise concat/print invalid (Type Mismatch).
        ' https://developer.roku.com/dev/docs/expressions-variables-types (Invalid type)
        if query = invalid then query = ""
        CleanupChild(dialog)
    end if
    m.searchDialog = invalid
    ? "SEARCH ACCEPT text=" + query
    if query <> "" then
        RunSearch(query)
    else
        m.rows.setFocus(true)
    end if
end sub

sub OnSearchCancelled(msg as Object)
    CleanupChild(m.searchDialog)
    m.searchDialog = invalid
    m.rows.setFocus(true)
end sub

sub OnSearchPicked(msg as Object)
    dialog = m.searchDialog
    rec = invalid
    if dialog <> invalid then
        rec = dialog.picked
        CleanupChild(dialog)
    end if
    m.searchDialog = invalid
    ? "SEARCH picked"
    if rec <> invalid then
        if rec.mediaType = "tv" then
            ShowSeriesDetails(rec)
        else
            ShowDetails(rec)
        end if
    else
        m.rows.setFocus(true)
    end if
end sub

sub RunSearch(query as String)
    m.query = query
    ' Search mode BEFORE the async task: OnSearchResponse drops responses
    ' while not inSearch, which silently killed every DONE-key search.
    m.inSearch = true
    ' Fresh query: drop anything an earlier search accumulated so pages of
    ' two different queries can never end up in one row, and cancel the old
    ' query's in-flight page (its late response would otherwise land in the
    ' middle of this one).
    SearchStopTask()
    m.searchResults = []
    m.searchPage = 0
    m.searchPages = 1
    m.searchLoading = false
    m.searchMoreIndex = -1
    SearchFetchPage(1)
end sub

' One page at a time. Pages accumulate in m.searchResults, so the results row
' only ever grows: the user keeps scrolling one continuous list instead of
' losing their place on every "next page".
'
' OWN TASK, NOT THE SHARED ONE: this used to call RunApiTask, which stores
' the node in m.activeTask — the SAME field the home-row loader and the
' watchlist hydrator write. One concurrent fetch was enough to steal it, the
' search response was dropped as "not the current task", m.searchLoading was
' never cleared, and every later page returned at the guard below. Symptom
' on device: page 1 works, paging is silently dead after that. Same fix
' LiveTvScene applied to its premium and sudo lineups: a private task ref,
' a dedicated handler, and an isSameNode identity check.
sub SearchFetchPage(page as Integer)
    if m.searchLoading then return
    if page < 1 then return
    ' Hard cap: TMDB happily reports thousands of pages for a broad query.
    if page > 10 then return
    m.searchLoading = true
    m.searchPage = page
    if m.statusLabel <> invalid then
        label = "Searching for " + Chr(34) + m.query + Chr(34)
        if page > 1 then label = label + "  •  loading more (page " + page.ToStr() + ")"
        m.statusLabel.text = label + "..."
    end if
    SearchStopTask()
    task = CreateObject("roSGNode", "ApiTask")
    if task = invalid then
        ' Never leave the busy flag stuck: an unrecoverable m.searchLoading
        ' means paging is dead for the rest of the session.
        m.searchLoading = false
        m.statusLabel.text = "Search is not available right now. Try again - BACK goes home."
        m.rows.setFocus(true)
        return
    end if
    task.url = TmdbSearchUrl(m.cfg, m.query, page)
    task.headers = TmdbHeaders(m.cfg.tmdbKey)
    task.observeField("raw", "OnSearchResponse")
    m.searchTask = task
    task.control = "run"
end sub

' Stop the in-flight page and clear the busy flag together, so every caller
' (new query, BACK-to-home, superseded page) leaves search in a resumable
' state instead of waiting for a response that will be thrown away.
sub SearchStopTask()
    if m.searchTask <> invalid then
        m.searchTask.control = "stop"
        m.searchTask = invalid
    end if
    m.searchLoading = false
end sub

' Search response, identity-guarded against the PRIVATE task ref (audit
' finding — see SearchFetchPage). The busy flag is cleared on EVERY exit path:
' success, wrong mode, non-200, empty page, unusable node. A stuck
' m.searchLoading is unrecoverable without restarting the app, which is
' exactly what used to happen.
'
' IDENTITY FROM THE EVENT, not the mutable ref: m.searchTask can be
' reassigned between a task completing and this observer running.
' NODE COMPARISON RULE: `=`/`<>` on two nodes throws &h18 on this firmware —
' invalid-check first, then isSameNode().
sub OnSearchResponse(msg as Object)
    if m.searchTask = invalid then
        ' LoadHomeRows / RunSearch already tore the page down and cleared the
        ' flag; a straggler event must not resurrect search state.
        return
    end if
    src = msg.getRoSGNode()
    if src = invalid then
        m.searchTask = invalid
        m.searchLoading = false
        return
    end if
    if not src.isSameNode(m.searchTask) then
        ' A superseded page's late event: the CURRENT page still owns the flag.
        return
    end if
    m.searchTask = invalid
    m.searchLoading = false
    if not m.inSearch then return
    page = m.searchPage
    if src.status <> 200 or src.raw = "" or src.raw = invalid then
        m.statusLabel.text = "Search failed (HTTP " + src.status.ToStr() + "). Try again - BACK goes home."
        m.rows.setFocus(true)
        return
    end if
    m.searchPages = TmdbTotalPages(src.raw)
    movies = TmdbParseMovies(src.raw)
    ? "SEARCH page=" + page.ToStr() + " got=" + movies.count().ToStr() + " pages=" + m.searchPages.ToStr()
    if movies.count() = 0 then
        ' A page past the end (or an empty envelope) must NOT wipe what the
        ' user already has: keep the accumulated results, close the MORE tile
        ' at the last page that actually had titles, and only report "no
        ' matches" when nothing at all was ever collected.
        if m.searchResults.count() = 0 then
            ShowEmptyResults()
            return
        end if
        if page < m.searchPages then m.searchPages = page
        ShowResults(m.searchResults, false)
        return
    end if
    for each rec in movies
        m.searchResults.Push(rec)
    end for
    ' Only a brand new query resets the cursor; an appended page keeps it.
    ShowResults(m.searchResults, page = 1)
end sub

' ------------------------------------------------------------------
' Async helper task
' ------------------------------------------------------------------

sub RunApiTask(url as String, headers as Object, handlerName as String)
    task = CreateObject("roSGNode", "ApiTask")
    task.url = url
    if headers = invalid then
        headers = {}
    end if
    task.headers = headers
    task.observeField("raw", handlerName)
    m.activeTask = task
    task.control = "run"
end sub

' ------------------------------------------------------------------
' Details overlay
' ------------------------------------------------------------------

sub ShowSeriesDetails(rec as Object)
    if m.seriesScene <> invalid then
        CleanupChild(m.seriesScene)
        m.seriesScene = invalid
    end if
    scene = CreateObject("roSGNode", "SeriesDetailScene")
    scene.series = rec
    scene.observeField("done", "OnSeriesSceneDone")
    m.seriesScene = scene
    m.top.appendChild(scene)
    scene.setFocus(true)
end sub

sub OnSeriesSceneDone()
    CleanupChild(m.seriesScene)
    m.seriesScene = invalid
    PersistDrain()
    ' Episode playback (via SeriesDetailScene/EpisodeScene) also saves resume
    ' points to the registry; reload for fresh tile indicators.
    m.profiles = ProfilesLoad()
    RefreshProgressIndicators()
    m.rows.setFocus(true)
end sub

sub ShowLiveTv()
    if m.liveTvScene <> invalid then
        CleanupChild(m.liveTvScene)
        m.liveTvScene = invalid
    end if
    scene = CreateObject("roSGNode", "LiveTvScene")
    if scene = invalid then
        m.statusLabel.text = "Live TV is not available."
        return
    end if
    ' FEATURE 2: TMDB key path HomeScene -> LiveTvScene -> LiveTvTask so the
    ' Sudo Movies virtual channel uses the configured key (falls back to the
    ' bundled default inside the task when empty).
    if scene.hasField("tmdbKey") and m.cfg <> invalid then
        scene.tmdbKey = m.cfg.tmdbKey
    end if
    scene.observeField("done", "OnLiveTvDone")
    m.liveTvScene = scene
    m.top.appendChild(scene)
    g = scene.findNode("channelList")
    if g <> invalid then
        g.setFocus(true)
    else
        scene.setFocus(true)
    end if
end sub

sub OnLiveTvDone()
    CleanupChild(m.liveTvScene)
    m.liveTvScene = invalid
    m.rows.setFocus(true)
end sub

sub ShowDetails(rec as Object)
    if m.detailsGroup <> invalid then
        return
    end if
    m.selectedRec = rec

    g = CreateObject("roSGNode", "Rectangle")
    g.color = "0x05070DFF"
    g.width = 1920
    g.height = 1080
    g.translation = "[0,0]"
    m.detailsGroup = g

    if rec.backdrop <> "" and rec.backdrop <> invalid then
        bd = CreateObject("roSGNode", "Poster")
        bd.uri = rec.backdrop
        bd.width = 1920
        bd.height = 1080
        bd.translation = "[0,0]"
        ' Full-bleed like the hero (scaleToFill crops overflow) instead of
        ' scaleToFit, which letterboxed and read as a bordered template.
        bd.loadDisplayMode = "scaleToFill"
        g.appendChild(bd)
        dimOverlay = CreateObject("roSGNode", "Rectangle")
        dimOverlay.color = "0x05070DB3"
        dimOverlay.width = 1920
        dimOverlay.height = 1080
        dimOverlay.translation = "[0,0]"
        g.appendChild(dimOverlay)
        leftShade = CreateObject("roSGNode", "Rectangle")
        leftShade.color = "0x05070DE6"
        leftShade.width = 1100
        leftShade.height = 1080
        leftShade.translation = "[0,0]"
        g.appendChild(leftShade)
        bottomShadeA = CreateObject("roSGNode", "Rectangle")
        bottomShadeA.color = "0x05070D66"
        bottomShadeA.width = 1920
        bottomShadeA.height = 140
        bottomShadeA.translation = "[0,700]"
        g.appendChild(bottomShadeA)
        bottomShadeB = CreateObject("roSGNode", "Rectangle")
        bottomShadeB.color = "0x05070DB3"
        bottomShadeB.width = 1920
        bottomShadeB.height = 120
        bottomShadeB.translation = "[0,840]"
        g.appendChild(bottomShadeB)
        bottomShadeC = CreateObject("roSGNode", "Rectangle")
        bottomShadeC.color = "0x05070DFF"
        bottomShadeC.width = 1920
        bottomShadeC.height = 120
        bottomShadeC.translation = "[0,960]"
        g.appendChild(bottomShadeC)
    end if

    posterEdge = CreateObject("roSGNode", "Rectangle")
    posterEdge.color = "0xD42028FF"
    posterEdge.width = 216
    posterEdge.height = 306
    posterEdge.translation = "[116,146]"
    g.appendChild(posterEdge)
    posterBorder = CreateObject("roSGNode", "Rectangle")
    posterBorder.color = "0xFFFFFFFF"
    posterBorder.width = 208
    posterBorder.height = 298
    posterBorder.translation = "[120,150]"
    g.appendChild(posterBorder)
    poster = CreateObject("roSGNode", "Poster")
    poster.width = 200
    poster.height = 290
    poster.translation = "[124,154]"
    poster.loadDisplayMode = "scaleToFit"
    pUri = rec.poster
    ' Bigger TMDB size where quality matters: the details poster is the focus
    ' of this screen, so pull w500 via the stored path instead of the w342
    ' list-size URL. Guarded: only real TMDB paths, never pkg:/ fallbacks.
    if SafeStr(rec, "posterPath", "") <> "" then
        pUri = TmdbImageUrl(rec.posterPath, "w500")
    end if
    if pUri = "" or pUri = invalid then
        pUri = "pkg:/images/poster_placeholder.png"
    end if
    poster.uri = pUri
    g.appendChild(poster)
    m.detailsPoster = poster

    kickerBg = CreateObject("roSGNode", "Rectangle")
    kickerBg.color = "0xD42028FF"
    kickerBg.width = 240
    kickerBg.height = 40
    kickerBg.translation = "[440,96]"
    g.appendChild(kickerBg)
    kickerLabel = CreateObject("roSGNode", "Label")
    kickerLabel.translation = "[440,96]"
    kickerLabel.width = 240
    kickerLabel.height = 40
    kickerLabel.color = "0xFFFFFFFF"
    kickerLabel.font = "font:MediumSystemFont"
    kickerLabel.horizAlign = "center"
    kickerLabel.vertAlign = "center"
    kickerText = UCase(SafeStr(rec, "mediaType", ""))
    if kickerText = "TV" then
        kickerText = "TV SERIES"
    else if kickerText = "" then
        kickerText = "TITLE"
    end if
    kickerLabel.text = kickerText
    g.appendChild(kickerLabel)

titleLabel = CreateObject("roSGNode", "Label")
    titleLabel.text = rec.title
    titleLabel.font = "font:LargeBoldSystemFont"
    titleLabel.color = "0xFFFFFFFF"
    titleLabel.translation = "[440,130]"
    titleLabel.width = 1040
    titleLabel.height = 106
    titleLabel.maxLines = 3
    titleLabel.wrap = true
    titleLabel.horizAlign = "left"
    titleLabel.vertAlign = "top"
    g.appendChild(titleLabel)
    m.detailsTitle = titleLabel

    metaPill = CreateObject("roSGNode", "Rectangle")
    metaPill.color = "0x0B0E17E6"
    metaPill.width = 860
    metaPill.height = 40
    metaPill.translation = "[440,240]"
    g.appendChild(metaPill)
    metaPillEdge = CreateObject("roSGNode", "Rectangle")
    metaPillEdge.color = "0xD42028FF"
    metaPillEdge.width = 4
    metaPillEdge.height = 40
    metaPillEdge.translation = "[440,240]"
    g.appendChild(metaPillEdge)
    metaLabel = CreateObject("roSGNode", "Label")
    ' Inside the gold-on-dark pill above ([440,240] 860x40): the old rect sat
    ' 98px below the pill overlapping genres/overview, leaving the pill empty.
    metaLabel.translation = "[452,240]"
    metaLabel.width = 830
    metaLabel.height = 40
    metaLabel.color = "0xFFD75EFF"
    metaLabel.font = "font:LargeBoldSystemFont"
    metaLabel.vertAlign = "center"
    metaLabel.text = BuildMetaLine(rec)
    g.appendChild(metaLabel)
    m.detailsMeta = metaLabel

    genresLabel = CreateObject("roSGNode", "Label")
    genresLabel.translation = "[440,282]"
    genresLabel.width = 960
    genresLabel.height = 32
    genresLabel.color = "0x6B7280FF"
    genresLabel.font = "font:MediumSystemFont"
    genresLabel.text = rec.genres
    g.appendChild(genresLabel)
    m.detailsGenres = genresLabel

    overviewLabel = CreateObject("roSGNode", "Label")
    overviewLabel.translation = "[440,320]"
    overviewLabel.width = 960
    overviewLabel.height = 180
    overviewLabel.maxLines = 5
    overviewLabel.wrap = true
    overviewLabel.font = "font:MediumSystemFont"
    overviewLabel.color = "0x6B7280FF"
    overviewLabel.horizAlign = "left"
    overviewLabel.vertAlign = "top"
    if rec.overview <> "" then
        overviewLabel.text = rec.overview
    else
        overviewLabel.text = "No overview available."
    end if
    g.appendChild(overviewLabel)
    m.detailsOverview = overviewLabel

    ctaBg = CreateObject("roSGNode", "Rectangle")
    ctaBg.color = "0xFFFFFFFF"
    ctaBg.width = 320
    ctaBg.height = 44
    ctaBg.translation = "[460,530]"
    g.appendChild(ctaBg)
    ctaEdge = CreateObject("roSGNode", "Rectangle")
    ctaEdge.color = "0x0B0E17FF"
    ctaEdge.width = 320
    ctaEdge.height = 4
    ctaEdge.translation = "[460,530]"
    g.appendChild(ctaEdge)
    ctaLabel = CreateObject("roSGNode", "Label")
    ctaLabel.text = "PLAY"
    ctaLabel.font = "font:MediumBoldSystemFont"
    ctaLabel.color = "0x0B0E17FF"
    ctaLabel.translation = "[460,530]"
    ctaLabel.width = 320
    ctaLabel.height = 44
    ctaLabel.horizAlign = "center"
    ctaLabel.vertAlign = "center"
    g.appendChild(ctaLabel)

    entries = DetailsEntries()
    optionsContent = CreateObject("roSGNode", "ContentNode")
    for each entry in entries
        nd = optionsContent.createChild("ContentNode")
        nd.title = entry
    end for
    optionsList = CreateObject("roSGNode", "LabelList")
    optionsList.content = optionsContent
    optionsList.itemSize = "[480,64]"
    optionsList.numRows = entries.count()
    optionsList.translation = "[920,730]"
    optionsList.focusBitmapUri = "pkg:/images/btn_focus.png"
    optionsList.focusFootprintBitmapUri = "pkg:/images/btn_footprint.png"
    ' LabelList has no textColor/showFocusFootprint (Button-only); unfocused
    ' text color is "color". https://developer.roku.com/dev/docs/labellist
    optionsList.color = "0x9CA3AFFF"
    optionsList.focusedColor = "0xFFFFFFFF"
    optionsList.observeField("itemSelected", "OnDetailsOptionSelected")
    g.appendChild(optionsList)
    m.detailsList = optionsList

    detailsRule = CreateObject("roSGNode", "Rectangle")
    detailsRule.color = "0xD42028FF"
    detailsRule.width = 1920
    detailsRule.height = 5
    detailsRule.translation = "[0,0]"
    g.appendChild(detailsRule)

    ' Red hint tick (design review): every other hint bar in the app pairs
    ' tick x=48 with label x=64 — the opaque details group covers the home
    ' status bar, so the tick must be re-created inside it.
    backHintTick = CreateObject("roSGNode", "Rectangle")
    backHintTick.color = "0xD42028FF"
    backHintTick.translation = "[48,1021]"
    backHintTick.width = 6
    backHintTick.height = 40
    g.appendChild(backHintTick)

    backHint = CreateObject("roSGNode", "Label")
    backHint.text = "OK to select  •  PLAY plays  •  BACK returns"
    backHint.font = "font:MediumBoldSystemFont"
    backHint.color = "0x6B7280FF"
    backHint.translation = "[64,1016]"
    backHint.width = 1600
    backHint.height = 32
    backHint.vertAlign = "center"
    g.appendChild(backHint)

    m.top.appendChild(g)
    HomeFadeIn(g)
    optionsList.setFocus(true)
end sub

function BuildMetaLine(rec as Object) as String
    parts = []
    ' SafeStr-guarded (audit finding): rec.year was read unguarded; a
    ' hand-edited registry record with year=invalid would push invalid
    ' into parts and throw inside the join loop below.
    y = SafeStr(rec, "year", "")
    if y <> "" then
        parts.push(y)
    end if
    if rec.runtime <> "" and rec.runtime <> invalid then
        parts.push(rec.runtime.ToStr() + " min")
    end if
    if rec.rating <> "" and rec.rating <> invalid then
        parts.push("TMDB " + rec.rating.ToStr())
    end if
    mt = UCase(SafeStr(rec, "mediaType", ""))
    if mt = "TV" then
        parts.push("TV SERIES")
    else if mt = "MOVIE" then
        parts.push("MOVIE")
    end if
    s = ""
    for each p in parts
        if s <> "" then
            s = s + "   •   "
        end if
        s = s + p
    end for
    return s
end function

' Resume progress 0-100 for the red progress bar on tiles. Returns 0 when no
' numeric resume point exists (bar hidden, text suffix still shows).
function HomeProgressPct(rec as Object) as Integer
    if m.profiles = invalid then return 0
    pid = ProfilesGetActiveId(m.profiles)
    if pid = "" then return 0
    if rec = invalid then return 0
    r = ProfilesGetResume(m.profiles, pid, rec)
    if r = invalid then return 0
    p = ProfilesInt(r, "p", 0)
    d = ProfilesInt(r, "d", 0)
    if d <= 0 then return 0
    if p <= 0 then return 0
    pct = Int(p * 100 / d)
    if pct < 0 then pct = 0
    if pct > 100 then pct = 100
    return pct
end function

' Bold section header: ">" accent + uppercase + title count (ASCII only —
' the firmware fonts lack the ▶ glyph and show a tofu square).
function HomeRowTitle(text as String, total as Integer) as String
    head = UCase(text)
    head = "> " + head
    if total > 0 then
        head = head + "  •  " + total.ToStr()
    end if
    return head
end function

' Scannable 10-foot tile line for home rows: year plus star rating plus the
' resume suffix, so quality and progress read at a glance. Strings only,
' runtime TMDB data only, zero bundle cost.
function TileLine(rec as Object) as String
    line = SafeStr(rec, "year", "")
    rating = SafeStr(rec, "rating", "")
    if rating <> "" then
        if line <> "" then line = line + "  •  "
        line = line + rating + "/10"
    end if
    line = line + ProfilesTileSuffix(rec)
    return line
end function

' One source of truth for the details options: ShowDetails,
' RefreshDetailsWatchlistOption and OnDetailsOptionSelected all read this, so
' the handler is driven by entry labels (structure-proof) and never by a
' fragile index. Includes "Set up playback" when no stream backend is
' configured (e.g. the token was cleared), so playback is never a dead end.
function DetailsEntries() as Object
    entries = ["Watch now"]
    pid = ProfilesGetActiveId(m.profiles)
    inList = false
    if pid <> "" then
        inList = ProfilesWatchlistHas(m.profiles, pid, SafeStr(m.selectedRec, "tmdbId", ""), SafeStr(m.selectedRec, "mediaType", "movie"))
    end if
    if pid <> "" then
        if inList then
            entries.Push("Remove from watchlist")
        else
            entries.Push("Add to watchlist")
        end if
    end if
    if not ConfigIsConfigured(m.cfg) then
        entries.Push("Set up playback")
    end if
    ' Only offer a trailer for a real TMDB title: hand-edited registry rows
    ' and the "Next page" tile have no id to look one up with.
    if SafeStr(m.selectedRec, "tmdbId", "") <> "" then
        entries.Push("Play trailer")
    end if
    entries.Push("Back")
    return entries
end function

sub OnDetailsOptionSelected(msg as Object)
    index = m.detailsList.itemSelected
    if index = invalid or index < 0 then return
    entries = DetailsEntries()
    if index >= entries.count() then return
    action = entries[index]
    if action = "Watch now" then
        StartScrape()
    else if action = "Play trailer" then
        ' Driven by LABEL, not index, so inserting this entry above cannot
        ' break the other branches.
        TrailerOpen(m.selectedRec)
    else if action = "Back" then
        CloseDetails()
      else if action = "Set up playback" then
          ' The sub in this file is ShowSettingsMenu(). This used to call
          ' OpenSettingsMenu(), which does not exist anywhere in the project -
          ' Roku compiles an unknown sub name fine and only raises it at
          ' runtime, so picking this entry threw instead of opening settings.
          ShowSettingsMenu()
    else
        ToggleWatchlist()
    end if
end sub

' Toggle the current title in/out of the active profile's watchlist.
sub ToggleWatchlist()
    pid = ProfilesGetActiveId(m.profiles)
    if pid = "" or m.selectedRec = invalid then return
    tmdbId = SafeStr(m.selectedRec, "tmdbId", "")
    if tmdbId = "" then return
    nowIn = ProfilesWatchlistToggle(m.profiles, pid, m.selectedRec)
    PersistDrain()
    if nowIn then
        ShowToast("Added to watchlist")
    else
        ShowToast("Removed from watchlist")
    end if
    RefreshDetailsWatchlistOption()
    ' Row-presence mismatch (first item added while the row was skipped,
    ' or last item removed): rebuild all rows so indices stay correct.
    listCount = ProfilesWatchlistGet(m.profiles, pid).count()
    rowShown = (m.ROW_WATCHLIST <> invalid and m.ROW_WATCHLIST >= 0)
    if (listCount > 0) <> rowShown then
        LoadHomeRows()
        return
    end if
    if m.watchlistRowNode <> invalid then
        BuildWatchlistRowContent(m.watchlistRowNode, m.ROW_WATCHLIST)
    end if
end sub

' Rebuild the details options list so the watchlist entry label reflects the
' new membership state (focus stays on the list).
sub RefreshDetailsWatchlistOption()
    if m.detailsList = invalid or m.selectedRec = invalid then return
    entries = DetailsEntries()
    content = CreateObject("roSGNode", "ContentNode")
    for each entry in entries
        nd = content.createChild("ContentNode")
        nd.title = entry
    end for
    m.detailsList.content = content
    m.detailsList.numRows = entries.count()
    m.detailsList.setFocus(true)
end sub

' * (options) quick toggle: details overlay uses the selected record;
' otherwise the focused home tile (movies AND tv rows, continue row,
' watchlist row itself = remove). Tiles without a tmdbId get a gentle
' no-op toast.
function HomeOptionsQuickWatchlist() as Boolean
    pid = ProfilesGetActiveId(m.profiles)
    if pid = "" then
        ShowToast("Pick a profile first to use your watchlist")
        return true
    end if
    rec = invalid
    if m.detailsGroup <> invalid then
        rec = m.selectedRec
    else if not m.inSearch then
        ' Every home row (Continue, Watchlist, TMDB feed) carries real
        ' records now that the special action rows are rail-only.
        if m.focusedRow >= 0 and m.focusedRow < m.rowRecords.count() then
            recs = m.rowRecords[m.focusedRow]
            if recs <> invalid and m.focusedCol >= 0 and m.focusedCol < recs.count() then
                rec = recs[m.focusedCol]
            end if
        end if
    end if
    if rec = invalid or SafeStr(rec, "tmdbId", "") = "" then
        ShowToast("Nothing to save on this tile")
        return true
    end if
    nowIn = ProfilesWatchlistToggle(m.profiles, pid, rec)
    PersistDrain()
    if nowIn then
        ShowToast("Added to watchlist")
    else
        ShowToast("Removed from watchlist")
    end if
    RefreshDetailsWatchlistOption()
    ' Row-presence mismatch (first item added while the row was skipped,
    ' or last item removed): rebuild all rows so indices stay correct.
    listCount = ProfilesWatchlistGet(m.profiles, pid).count()
    rowShown = (m.ROW_WATCHLIST <> invalid and m.ROW_WATCHLIST >= 0)
    if (listCount > 0) <> rowShown then
        LoadHomeRows()
        return true
    end if
    if m.watchlistRowNode <> invalid then
        BuildWatchlistRowContent(m.watchlistRowNode, m.ROW_WATCHLIST)
    end if
    return true
end function

sub CloseDetails()
    StopHomeFade()
    CleanupChild(m.detailsGroup)
    m.detailsGroup = invalid
    m.detailsList = invalid
    m.detailsPoster = invalid
    m.detailsTitle = invalid
    m.detailsMeta = invalid
    m.detailsOverview = invalid
    m.detailsGenres = invalid
    m.selectedRec = invalid
    m.rows.setFocus(true)
end sub

sub RestoreDetailsFocus()
    if m.detailsGroup <> invalid and m.detailsList <> invalid then
        m.detailsList.setFocus(true)
    else
        m.rows.setFocus(true)
    end if
end sub

' ------------------------------------------------------------------
' Scraping streams + progress overlay
' ------------------------------------------------------------------

' True when any resolver task is currently in flight. Used by StartScrape to
' tell a live fetch from an orphaned progress overlay (see StartScrape guard).
function TasksActive() as Boolean
    if m.activeTask <> invalid then return true
    ' Search owns its own task now, so it has to be counted separately or
    ' StartScrape would treat a live search as an orphaned progress overlay.
    if m.searchTask <> invalid then return true
    if m.femboxTask <> invalid then return true
    if m.vixTask <> invalid then return true
    if m.scrapeTask <> invalid then return true
    return false
end function

sub StartScrape()
    rec = m.selectedRec
    if rec = invalid then
        return
    end if
    if rec.tmdbId = "" or rec.tmdbId = invalid then
        ' Toast, not statusLabel: the details overlay covers the home status
        ' line, so this message would be invisible (dead end).
        ShowToast("No TMDB id for this title.")
        RestoreDetailsFocus()
        return
    end if

    ' Guard: ignore repeated OK presses while a fetch is already in flight.
    ' Without this, a second ShowProgress orphans the first group (HideProgress
    ' only removes the latest) and starts duplicate resolver tasks.
    if m.progressGroup <> invalid then
        ' A resolve chain that throws can leave the overlay up with no task in
        ' flight, so the guard silently eats every later Watch-now press until
        ' the app is restarted. Heal it: if no resolver task is actually live,
        ' tear the orphaned overlay down and let this press proceed.
        if TasksActive() then
            return
        else
            HideProgress()
        end if
    end if

    ' Fail fast before showing the modal when there is no token, so the popup
    ' never flashes for a single frame. Same message StartFembox() would show.
    ' Toast, not statusLabel: the details overlay covers the home status line.
    if FebboxGetActiveToken(m.cfg) = "" then
        ShowToast("Set your free Febbox token in Settings to enable playback.")
        RestoreDetailsFocus()
        return
    end if
    ' Surface a clearly-expired Febbox token up front instead of a generic
    ' quota/403 down the chain.
    if FebboxTokenExpired(FebboxGetActiveToken(m.cfg)) then
        ShowToast("Febbox token expired - re-paste a fresh one in Settings.")
        RestoreDetailsFocus()
        return
    end if

    ShowProgress(rec)
    m.triedScrape = false
    m.triedFem = false
    m.triedVix = false
    m.femRetries = 0
    m.femCandidates = []
    m.vixCandidates = []

    ? "SCRAPE start tmdbId=" + SafeStr(rec, "tmdbId", "")
    
    ' Strict Priority: 1. Febbox (token rotate+retry, known-good) ->
    ' 2. VixSrc (listed alongside Febbox) -> 3. Urban extra providers ->
    ' 4. Scrape/providers. (Movy removed: dead scraper, caused silent crashes.)
    StartFembox()
end sub

sub StartFembox()
    rec = m.selectedRec
    if rec = invalid then
        return
    end if
    m.triedFem = true
    token = FebboxGetActiveToken(m.cfg)
    if token = "" then
        HideProgress()
        ShowToast("Set your free Febbox token in Settings to enable playback.")
        RestoreDetailsFocus()
        return
    end if
    if m.progressSmall <> invalid then
        m.progressSmall.text = "Asking Febbox (uses your 10 GB quota)..."
    end if
    task = CreateObject("roSGNode", "FemboxTask")
    task.tmdbId = rec.tmdbId
    task.mediaType = "movie"
    if rec.mediaType = "tv" then task.mediaType = "tv"
    task.season = "1"
    if rec.season <> invalid and rec.season <> "" then task.season = rec.season
    task.episode = "1"
    if rec.episode <> invalid and rec.episode <> "" then task.episode = rec.episode
    task.token = token
    task.observeField("status", "OnFemboxStatus")
    m.femboxTask = task
    task.control = "run"
end sub

sub StartVixSrc()
    rec = m.selectedRec
    if rec = invalid then
        return
    end if
    m.triedVix = true
    if m.progressSmall <> invalid then
        m.progressSmall.text = "Checking VixSrc (no quota used)..."
    end if
    task = CreateObject("roSGNode", "VixSrcTask")
    task.tmdbId = rec.tmdbId
    task.mediaType = "movie"
    if rec.mediaType = "tv" then task.mediaType = "tv"
    task.season = "1"
    if rec.season <> invalid and rec.season <> "" then task.season = rec.season
    task.episode = "1"
    if rec.episode <> invalid and rec.episode <> "" then task.episode = rec.episode
    task.observeField("status", "OnVixSrcStatus")
    m.vixTask = task
    task.control = "run"
end sub

sub OnVixSrcStatus()
    task = m.vixTask
    m.vixTask = invalid
    if task = invalid then
        ' Urban removed: fall through to providers chain.
        if m.cfg.providerApiBase <> "" and not m.triedScrape then
            RunScrapeTask()
        else
            HideProgress()
            ShowToast("No streams found. Try SEARCH or another title.")
        end if
        return
    end if
    nv = 0
    if task.candidates <> invalid then
        nv = task.candidates.count()
    end if
    ? "VIX status=" + task.status.ToStr() + " cands=" + nv.ToStr()
    ' Keep VixSrc results.
    m.vixCandidates = []
    if task.status = 200 and task.candidates <> invalid then
        m.vixCandidates = task.candidates
    end if
    ' Merge Fembox + VixSrc candidates (Urban removed).
    merged = []
    if m.femCandidates <> invalid then
        for each c in m.femCandidates
            merged.Push(c)
        end for
    end if
    if m.vixCandidates <> invalid then
        for each c in m.vixCandidates
            merged.Push(c)
        end for
    end if
    ? "VIX merged=" + merged.count().ToStr()
    if merged.count() > 0 then
        HideProgress()
        OnStreamsReady(merged)
        return
    end if
    ' Febbox and VixSrc both empty: fall through to the providers chain.
    if m.cfg.providerApiBase <> "" and not m.triedScrape then
        RunScrapeTask()
    else
        HideProgress()
        if merged.count() = 0 then
            ShowToast("No streams found. Try SEARCH or another title.")
        end if
    end if
end sub

' Archive.org leg: a real, stable, key-free catalog with playable MP4s.
' Its candidates join the merge so the picker shows more providers.
sub RunScrapeTask()
    rec = m.selectedRec
    m.triedScrape = true
    if m.progressSmall <> invalid then
        m.progressSmall.text = "Scanning free providers (no quota used)..."
    end if
    task = CreateObject("roSGNode", "ScrapeTask")
    task.providerApiBase = m.cfg.providerApiBase
    task.movieTitle = rec.title
    task.releaseYear = rec.year
    task.tmdbId = rec.tmdbId
    task.target = "native"
    task.observeField("progress", "OnScrapeProgress")
    task.observeField("status", "OnScrapeStatus")
    task.observeField("errorDetail", "OnScrapeErrorDetail")
    m.scrapeTask = task
    task.control = "run"
end sub

sub ShowProgress(rec as Object)
    ' Belt-and-braces: StartScrape already guards, but never stack two modals.
    if m.progressGroup <> invalid then
        return
    end if
    g = CreateObject("roSGNode", "Rectangle")
    ' Fully opaque scrim: the details screen underneath is left-weighted
    ' (poster at x=120, text block from x=460), and letting it shine through a
    ' translucent dim biases the eye so the centered card reads as shifted.
    g.color = "0x000000FF"
    g.width = 1920
    g.height = 1080
    g.translation = "[0,0]"
    m.progressGroup = g

    card = CreateObject("roSGNode", "Rectangle")
    card.color = "0x0B0E17F5"
    card.width = 840
    card.height = 300
    card.translation = "[540,390]"
    g.appendChild(card)

    cardAccent = CreateObject("roSGNode", "Rectangle")
    cardAccent.color = "0xD42028FF"
    cardAccent.width = 840
    cardAccent.height = 6
    cardAccent.translation = "[540,384]"
    g.appendChild(cardAccent)
    cardLeftBar = CreateObject("roSGNode", "Rectangle")
    cardLeftBar.color = "0xD42028FF"
    cardLeftBar.width = 8
    cardLeftBar.height = 300
    cardLeftBar.translation = "[540,390]"
    g.appendChild(cardLeftBar)

    big = CreateObject("roSGNode", "Label")
    big.width = 720
    big.height = 100
    big.translation = "[600,448]"
    big.horizAlign = "center"
    big.vertAlign = "center"
    big.font = "font:MediumBoldSystemFont"
    big.color = "0xFFFFFFF2"
    big.wrap = true
    big.maxLines = 2
    big.text = "Finding streams for " + rec.title + "..."
    g.appendChild(big)

    small = CreateObject("roSGNode", "Label")
    small.width = 720
    small.height = 40
    small.translation = "[600,556]"
    small.horizAlign = "center"
    small.vertAlign = "center"
    ' Single centered line: wrap + fixed height clips any overlong status to
    ' one full line, so long strings truncate symmetrically instead of
    ' spilling and making the card look off-center. (Per LabelBase docs,
    ' height > 0 means maxLines is ignored, so height alone bounds it.)
    small.wrap = true
    small.font = "font:MediumSystemFont"
    small.color = "0x9CA3AFFF"
    small.text = "Scanning providers - this can take up to a minute"
    g.appendChild(small)
    m.progressSmall = small

    progressAccent = CreateObject("roSGNode", "Rectangle")
    progressAccent.color = "0xD42028FF"
    progressAccent.width = 200
    progressAccent.height = 6
    progressAccent.translation = "[860,624]"
    g.appendChild(progressAccent)

    cancelHint = CreateObject("roSGNode", "Label")
    cancelHint.text = "BACK cancels this fetch"
    cancelHint.font = "font:MediumSystemFont"
    cancelHint.color = "0x6B7280FF"
    cancelHint.width = 720
    cancelHint.height = 40
    cancelHint.translation = "[600,645]"
    cancelHint.horizAlign = "center"
    cancelHint.vertAlign = "center"
    g.appendChild(cancelHint)

    m.top.appendChild(g)
    HomeFadeIn(g)
    ' Move key focus into the modal. The details LabelList underneath sits at
    ' x=460 (left of center); leaving it focused keeps its bright focus bitmap
    ' glowing through the scrim as a left-side anchor that makes the centered
    ' card appear shifted right. This also stops OK presses reaching the list
    ' and re-firing StartScrape while a fetch is in flight.
    g.setFocus(true)
end sub

sub OnScrapeProgress()
    task = m.scrapeTask
    if task <> invalid and m.progressSmall <> invalid then
        p = task.progress
        if p <> "" and p <> invalid then
            m.progressSmall.text = p
        end if
    end if
end sub

sub OnScrapeErrorDetail()

end sub

sub OnScrapeStatus()
    task = m.scrapeTask
    if task = invalid then
        return
    end if
    m.scrapeTask = invalid
    if task.status = 200 then
        candidates = task.candidates
        if candidates <> invalid and candidates.count() > 0 then
            HideProgress()
            OnStreamsReady(candidates)
            return
        end if
    end if
    if m.cfg.febboxToken <> "" and not m.triedFem then
        ? "SCRAPE empty/failed, falling back to Febbox"
        StartFembox()
        return
    end if
    HideProgress()
    ' Toast, not statusLabel: the details overlay is open here and covers the
    ' home status line, so these results would never be seen.
    if task.status = 200 then
        ShowToast("No playable sources found. Try another title.")
    else
        detail = task.errorDetail
        if detail = "" or detail = invalid then
            detail = "Scrape failed (code " + task.status.ToStr() + ")."
        end if
        if detail.Len() > 60 then detail = "No playable sources found. Try another title."
        ShowToast(detail)
    end if
    RestoreDetailsFocus()
end sub

sub OnFemboxStatus()
    task = m.femboxTask
    m.femboxTask = invalid
    if task = invalid then
        return
    end if
    if task.errorDetail <> invalid and task.errorDetail <> "" then
        m.lastFemError = task.errorDetail
    end if
    nc = 0
    if task.candidates <> invalid then
        nc = task.candidates.count()
    end if
    ? "FEM status=" + task.status.ToStr() + " cands=" + nc.ToStr()
    if task.status = 200 then
        if nc > 0 then
            ' Keep Febbox results, then also fetch VixSrc so the user can
            ' choose between FEM and VIX entries in one picker.
            m.femCandidates = task.candidates
            if m.progressSmall <> invalid then
                m.progressSmall.text = "Checking VixSrc (no quota used)..."
            end if
            StartVixSrc()
            return
        end if
        ' 200 but zero sources -> treat like a quota/empty result so we
        ' rotate to the next saved token instead of failing outright.
        if m.cfg.febboxTokens <> invalid and m.femRetries < m.cfg.febboxTokens.count() then
            m.femRetries = m.femRetries + 1
            nextToken = FebboxRotateToken(m.cfg)
            if nextToken <> "" then
                ? "FEM 200-empty, rotating to next token"
                StartFembox()
                return
            end if
        end if
    end if

    ' Rotate to the next saved token and retry when the active token is
    ' rejected or hits its quota (401/403/400/429/204 = no usable links).
    if (task.status = 401 or task.status = 403 or task.status = 400 or task.status = 429 or task.status = 204) and m.cfg.febboxTokens <> invalid and m.femRetries < m.cfg.febboxTokens.count() then
        m.femRetries = m.femRetries + 1
        nextToken = FebboxRotateToken(m.cfg)
        if nextToken <> "" then
            ? "FEM token rejected/quota, retrying with next token"
            StartFembox()
            return
        end if
    end if

    if m.cfg.providerApiBase <> "" and not m.triedScrape then
        ? "FEM failed, falling back to providers"
        RunScrapeTask()
    else
        ' Febbox is done (success was already routed to VixSrc above, so
        ' reaching here means empty/exhausted). Still check VixSrc so the
        ' user gets its entries as options before we give up.
        m.femCandidates = []
        StartVixSrc()
        return
    end if
end sub

sub ShowResolveFailure()
    if Instr(1, LCase(m.lastFemError), "expired") > 0 then
        ShowToast("Febbox token expired - re-paste a fresh one in Settings.")
    else
        ' Toast: the details overlay covers the home status line (dead end).
        ShowToast("No playable sources found. Try another title.")
    end if
    RestoreDetailsFocus()
end sub

' ------------------------------------------------------------------
' Toast (bottom-center fade, never steals focus, guards stacking)
' ------------------------------------------------------------------

sub InitToast()
    if m.toastGroup <> invalid then return
    g = CreateObject("roSGNode", "Rectangle")
    g.color = "0x0B0E17F5"
    g.width = 900
    g.height = 56
    g.translation = "[510,880]"
    g.opacity = 0
    g.visible = false
    toastAccent = CreateObject("roSGNode", "Rectangle")
    toastAccent.color = "0xD42028FF"
    toastAccent.width = 900
    toastAccent.height = 4
    toastAccent.translation = "[0,-4]"
    g.appendChild(toastAccent)
    lbl = CreateObject("roSGNode", "Label")
    lbl.width = 860
    lbl.height = 56
    lbl.translation = "[20,0]"
    lbl.horizAlign = "center"
    lbl.vertAlign = "center"
    lbl.font = "font:MediumSystemFont"
    lbl.color = "0xFFFFFFFF"
    lbl.wrap = true
    lbl.maxLines = 1
    g.appendChild(lbl)
    m.toastLabel = lbl
    timer = CreateObject("roSGNode", "Timer")
    timer.duration = 2.6
    timer.repeat = false
    timer.observeField("fire", "OnToastTimerFire")
    m.toastTimer = timer
    m.top.appendChild(timer)
    m.top.appendChild(g)
    m.toastGroup = g
end sub

sub ShowToast(text as String)
    InitToast()
    if m.toastGroup = invalid then return
    if m.toastLabel <> invalid then
        m.toastLabel.text = text
    end if
    ' Always move the toast to the top of the child list: modals opened after
    ' the toast group was first created would otherwise render ON TOP of it
    ' and hide the message (last child wins in SceneGraph z-order).
    CleanupChild(m.toastGroup)
    m.top.appendChild(m.toastGroup)
    ' Instant show and hide: programmatic opacity animation proved unreliable
    ' on this firmware (toasts stranded invisible or visible), so the toast is
    ' one behavior everywhere — appear, wait 2.6s, disappear, never steals focus.
    m.toastGroup.visible = true
    m.toastGroup.opacity = 1.0
    if m.toastTimer <> invalid then
        m.toastTimer.control = "stop"
        m.toastTimer.control = "start"
    end if
end sub

function MakeToastAnim(fromV as Float, toV as Float, dur as Float) as Object
    anim = CreateObject("roSGNode", "Animation")
    anim.duration = dur
    anim.repeat = false
    interp = CreateObject("roSGNode", "FloatFieldInterpolator")
    interp.fieldToInterp = "opacity"
    interp.key = [0.0, 1.0]
    interp.keyValue = [fromV, toV]
    interp.target = m.toastGroup
    anim.appendChild(interp)
    anim.observeField("state", "OnToastAnimState")
    return anim
end function

sub OnToastTimerFire()
    if m.toastGroup = invalid then return
    m.toastGroup.visible = false
end sub

sub OnToastAnimState()
    a = m.toastAnim
    if a = invalid then return
    if a.state = "stopped" and m.toastPhase = "out" then
        if m.toastGroup <> invalid then
            m.toastGroup.visible = false
        end if
        m.toastAnim = invalid
    end if
end sub

' ------------------------------------------------------------------
' Modal motion: one shared 220ms fade-in (outCubic, never blocks input).
' Mirrors the toast Animation + FloatFieldInterpolator pattern, but the
' Animation node is parented inside the modal so it ticks in-tree and is
' removed when it stops (no leak). Single-flight: opening a new modal
' stops the previous fade first; every teardown path stops it too.
' ------------------------------------------------------------------

sub HomeFadeIn(node as Object)
    if node = invalid then return
    StopHomeFade()
    ' Fade DISABLED: programmatic opacity animation proved unreliable on
    ' this firmware (modals stranded at opacity 0 = invisible but focused,
    ' which looks exactly like a frozen home screen). Show immediately.
    node.opacity = 1.0
end sub

sub StopHomeFade()
    if m.modalAnim = invalid then return
    m.modalAnim.control = "stop"
    HomeDetachAnim()
end sub

sub HomeDetachAnim()
    if m.modalAnim <> invalid and m.modalAnimParent <> invalid then
        kids = m.modalAnimParent.getChildren(-1, 0)
        for each k in kids
            if k.isSameNode(m.modalAnim) then
                m.modalAnimParent.removeChild(m.modalAnim)
                exit for
            end if
        end for
    end if
    m.modalAnim = invalid
    m.modalAnimParent = invalid
end sub

sub OnHomeFadeState()
    a = m.modalAnim
    if a = invalid then return
    if a.state = "stopped" then
        HomeDetachAnim()
    end if
end sub

sub HideProgress()
    StopHomeFade()
    CleanupChild(m.progressGroup)
    m.progressGroup = invalid
    ' The label node was removed with the group; clear the stale pointer so
    ' late progress callbacks cannot write to a detached node.
    m.progressSmall = invalid
end sub

sub CancelProgress()
    ' Back pressed while the fetch modal is up: stop any in-flight resolver
    ' so its observer cannot resurrect UI after we tear the modal down.
    if m.activeTask <> invalid then
        m.activeTask.control = "stop"
        m.activeTask = invalid
    end if
    if m.femboxTask <> invalid then
        m.femboxTask.control = "stop"
        m.femboxTask = invalid
    end if
    if m.vixTask <> invalid then
        m.vixTask.control = "stop"
        m.vixTask = invalid
    end if
    if m.scrapeTask <> invalid then
        m.scrapeTask.control = "stop"
        m.scrapeTask = invalid
    end if
    HideProgress()
    ' Toast: the details overlay (still open underneath) covers the status line.
    ShowToast("Fetch cancelled.")
    RestoreDetailsFocus()
end sub

sub OnStreamsReady(candidates as Object)
    if candidates = invalid or candidates.count() = 0 then
        ' Toast: the details overlay covers the home status line (dead end).
        ShowToast("No playable sources found. Try another title.")
        RestoreDetailsFocus()
        return
    end if
    m.pendingCandidates = candidates
    if m.autoPlay = true then
        ' Deep-link / PLAY-key path only: explicit user intent to play now.
        m.autoPlay = false
        LaunchPlayback(candidates[0])
    else
        ' Always show the picker — even for a single source. Single-candidate
        ' auto-play meant one empty backend silently removed all choice, and
        ' the old remembered-source skip did the same for multiples.
        ShowSourcePicker(candidates)
    end if
end sub

' ------------------------------------------------------------------
' Source picker
' ------------------------------------------------------------------

sub ShowSourcePicker(candidates as Object)
    g = CreateObject("roSGNode", "Rectangle")
    g.color = "0x0B0E17F2"
    g.width = 1920
    g.height = 1080
    g.translation = "[0,0]"
    m.sourcePickerGroup = g

    title = CreateObject("roSGNode", "Label")
    title.text = "CHOOSE A SOURCE"
    title.font = "font:MediumBoldSystemFont"
    title.color = "0xF5F5F5FF"
    title.translation = "[460,196]"
    title.width = 1000
    title.height = 50
    title.horizAlign = "center"
    title.vertAlign = "center"
    g.appendChild(title)

    sourceAccent = CreateObject("roSGNode", "Rectangle")
    sourceAccent.color = "0xD42028FF"
    sourceAccent.width = 120
    sourceAccent.height = 4
    sourceAccent.translation = "[900,248]"
    g.appendChild(sourceAccent)

    hint = CreateObject("roSGNode", "Label")
    ' Short Medium hint: the 1000px centered line clips ~66-char strings.
    hint.text = "FEM = Febbox  •  VIX = VixSrc  •  more below  •  S = subtitles"
    hint.font = "font:SmallSystemFont"
    hint.color = "0x9CA3AFFF"
    hint.translation = "[460,260]"
    hint.width = 1000
    hint.height = 30
    hint.horizAlign = "center"
    g.appendChild(hint)

    panel = CreateObject("roSGNode", "Rectangle")
    panel.color = "0x0B121DFF"
    panel.width = 920
    panel.height = 488
    panel.translation = "[500,296]"
    g.appendChild(panel)
    panelEdge = CreateObject("roSGNode", "Rectangle")
    panelEdge.color = "0x1F2937FF"
    panelEdge.width = 920
    panelEdge.height = 2
    panelEdge.translation = "[500,294]"
    g.appendChild(panelEdge)
    panelLeftBar = CreateObject("roSGNode", "Rectangle")
    panelLeftBar.color = "0xD42028FF"
    panelLeftBar.width = 8
    panelLeftBar.height = 488
    panelLeftBar.translation = "[500,296]"
    g.appendChild(panelLeftBar)

    content = CreateObject("roSGNode", "ContentNode")
    for each cand in candidates
        nd = content.createChild("ContentNode")
        label = cand.label
        if label = "" or label = invalid then
            label = "Source"
        end if
        if cand.subtitles <> invalid and cand.subtitles.count() > 0 then
            label = label + "   (S)"
        end if
        nd.title = label
    end for
    list = CreateObject("roSGNode", "LabelList")
    list.content = content
    list.itemSize = "[840,52]"
    list.numRows = 8
    list.translation = "[540,306]"
    list.focusBitmapUri = "pkg:/images/btn_focus.png"
    list.focusFootprintBitmapUri = "pkg:/images/btn_footprint.png"
    ' LabelList has no textColor/showFocusFootprint (Button-only); unfocused
    ' text color is "color". https://developer.roku.com/dev/docs/labellist
    list.color = "0x9CA3AFFF"
    list.focusedColor = "0xFFFFFFFF"
    list.observeField("itemSelected", "OnSourcePicked")
    g.appendChild(list)
    m.sourceList = list

    dismissHint = CreateObject("roSGNode", "Label")
    dismissHint.text = "OK plays  •  BACK dismisses"
    dismissHint.font = "font:MediumSystemFont"
    dismissHint.color = "0x6B7280FF"
    dismissHint.translation = "[540,732]"
    dismissHint.width = 840
    dismissHint.height = 40
    dismissHint.horizAlign = "center"
    dismissHint.vertAlign = "center"
    g.appendChild(dismissHint)

    m.top.appendChild(g)
    HomeFadeIn(g)
    list.setFocus(true)
end sub

sub OnSourcePicked(msg as Object)
    if m.sourceList = invalid then
        return
    end if
    index = m.sourceList.itemSelected
    if index < 0 or m.pendingCandidates = invalid or index >= m.pendingCandidates.count() then
        return
    end if
    cand = m.pendingCandidates[index]
    StopHomeFade()
    CleanupChild(m.sourcePickerGroup)
    m.sourcePickerGroup = invalid
    m.sourceList = invalid
    ConfigSetLastSource(SourceKey(cand))
    LaunchPlayback(cand)
end sub

' ------------------------------------------------------------------
' Playback
' ------------------------------------------------------------------

sub LaunchPlayback(cand as Object)
    if m.selectedRec <> invalid then
        cand.title = m.selectedRec.title
    end if
    ' Guard: a provider can hand back a candidate without a url; .Left() on
    ' invalid is a render-thread Type Mismatch that kills the channel.
    url = SafeStr(cand, "url", "")
    if url = "" then
        ' Toast: the details overlay covers the home status line (dead end).
        ShowToast("This source returned no playable URL. Pick another source.")
        RestoreDetailsFocus()
        return
    end if
    ? "PLAY url=" + url.Left(80)
    playback = CreateObject("roSGNode", "PlaybackScene")
    rr = {}
    if m.selectedRec <> invalid then
        rr = {
            tmdbId: SafeStr(m.selectedRec, "tmdbId", ""),
            mediaType: SafeStr(m.selectedRec, "mediaType", "movie"),
            season: SafeStr(m.selectedRec, "season", ""),
            episode: SafeStr(m.selectedRec, "episode", ""),
            title: SafeStr(m.selectedRec, "title", ""),
            poster: SafeStr(m.selectedRec, "poster", "")
        }
    end if
    ' resumeRec first: the movie observer fires StartPlayback, which reads it.
    playback.resumeRec = rr
    playback.movie = cand
    playback.observeField("done", "OnPlaybackDone")
    m.playback = playback
    m.top.appendChild(playback)
    v = playback.findNode("videoPlayer")
    if v <> invalid then
        v.setFocus(true)
    else
        playback.setFocus(true)
    end if
end sub

sub OnPlaybackDone()
    if m.playback <> invalid then
        CleanupChild(m.playback)
    end if
    m.playback = invalid
    PersistDrain()
    ' PlaybackScene wrote resume points straight to the registry; reload so
    ' tile indicators and later lookups see fresh data.
    m.profiles = ProfilesLoad()
    if m.ROW_CONTINUE = invalid or m.ROW_CONTINUE < 0 then
        ' Continue row was skipped (was empty): a resume was just saved, so
        ' rebuild rows to reveal it. Otherwise just refresh indicators.
        LoadHomeRows()
    else
        RefreshProgressIndicators()
    end if
    RestoreDetailsFocus()
end sub

' ------------------------------------------------------------------
' Settings: menu + stepped Keypad editors (Keypad component kept).
' The old forced linear walk (step 1 -> 2 -> 3, BACK killed everything) is
' replaced by a menu card where every setting is visible with its step
' indicator and current state. Each editor saves instantly and returns to the
' menu, so editing only the token never drags you through the other steps.
' ------------------------------------------------------------------

sub ShowSettingsMenu()
    if m.settingsMenuGroup <> invalid then
        return
    end if
    g = CreateObject("roSGNode", "Rectangle")
    g.color = "0x000000E6"
    g.width = 1920
    g.height = 1080
    g.translation = "[0,0]"
    m.settingsMenuGroup = g

    cardGlow = CreateObject("roSGNode", "Rectangle")
    cardGlow.color = "0xD4202844"
    cardGlow.width = 920
    cardGlow.height = 500
    cardGlow.translation = "[500,220]"
    g.appendChild(cardGlow)
    card2 = CreateObject("roSGNode", "Rectangle")
    card2.color = "0x0B0E17F5"
    card2.width = 900
    card2.height = 480
    card2.translation = "[510,230]"
    g.appendChild(card2)

    cardAccent = CreateObject("roSGNode", "Rectangle")
    cardAccent.color = "0xD42028FF"
    cardAccent.width = 900
    cardAccent.height = 6
    cardAccent.translation = "[510,224]"
    g.appendChild(cardAccent)
    cardLeftBar = CreateObject("roSGNode", "Rectangle")
    cardLeftBar.color = "0xD42028FF"
    cardLeftBar.width = 8
    cardLeftBar.height = 480
    cardLeftBar.translation = "[510,230]"
    g.appendChild(cardLeftBar)

    title = CreateObject("roSGNode", "Label")
    title.text = "SETTINGS"
    title.font = "font:MediumBoldSystemFont"
    title.color = "0xF5F5F5FF"
    title.translation = "[560,266]"
    title.width = 800
    title.height = 48
    title.horizAlign = "center"
    title.vertAlign = "center"
    g.appendChild(title)

    hint = CreateObject("roSGNode", "Label")
    hint.text = "Pick a setting to edit  •  Edits save instantly  •  BACK closes"
    hint.font = "font:SmallSystemFont"
    hint.color = "0x9CA3AFFF"
    hint.translation = "[560,320]"
    hint.width = 800
    hint.height = 30
    hint.horizAlign = "center"
    hint.vertAlign = "center"
    g.appendChild(hint)

    ' Step indicators + live state per entry, rebuilt on every open.
    febboxState = "[ NOT SET ]"
    if FebboxGetActiveToken(m.cfg) <> "" then
        febboxState = "[ SET ]"
    end if
    providerState = "[ NOT SET ]"
    if m.cfg.providerApiBase <> "" then
        providerState = "[ SET ]"
    end if
    content = CreateObject("roSGNode", "ContentNode")
    ' Short labels: the 800px rows clip ~46-char MediumBold strings, so the
    ' step counters live in the editor titles instead of here.
    entries = [
        "1. FEBBOX TOKEN  •  " + febboxState,
        "2. PROVIDER URL  •  " + providerState,
        "3. TMDB KEY  •  [ BUILT IN ]",
        "DONE - BACK TO HOME"
    ]
    for each entry in entries
        nd = content.createChild("ContentNode")
        nd.title = entry
    end for
    list = CreateObject("roSGNode", "LabelList")
    list.content = content
    list.itemSize = "[800,56]"
    list.numRows = 4
    list.translation = "[560,380]"
    list.focusBitmapUri = "pkg:/images/btn_focus.png"
    list.focusFootprintBitmapUri = "pkg:/images/btn_footprint.png"
    ' LabelList has no textColor/showFocusFootprint (Button-only); unfocused
    ' text color is "color". https://developer.roku.com/dev/docs/labellist
    list.color = "0x9CA3AFFF"
    list.focusedColor = "0xFFFFFFFF"
    list.observeField("itemSelected", "OnSettingsMenuPicked")
    g.appendChild(list)
    m.settingsMenuList = list

    menuHint = CreateObject("roSGNode", "Label")
    menuHint.text = "Febbox token enables playback  •  Provider and TMDB key are optional"
    menuHint.font = "font:MediumSystemFont"
    menuHint.color = "0x6B7280FF"
    menuHint.translation = "[560,640]"
    menuHint.width = 800
    menuHint.height = 40
    menuHint.horizAlign = "center"
    menuHint.vertAlign = "center"
    g.appendChild(menuHint)

    m.top.appendChild(g)
    HomeFadeIn(g)
    list.setFocus(true)
    ? "SETTINGS menu opened"
end sub

sub HideSettingsMenu()
    StopHomeFade()
    CleanupChild(m.settingsMenuGroup)
    m.settingsMenuGroup = invalid
    m.settingsMenuList = invalid
end sub

sub OnSettingsMenuPicked(msg as Object)
    if m.settingsMenuList = invalid then return
    index = m.settingsMenuList.itemSelected
    if index = invalid or index < 0 or index > 3 then return
    if index = 0 then
        OpenSettingEditor("febbox")
    else if index = 1 then
        OpenSettingEditor("provider")
    else if index = 2 then
        OpenSettingEditor("tmdb")
    else
        CloseSettings()
    end if
end sub

' One stepped editor per setting (Keypad kept). The step number in the title
' matches the menu entry, so the wizard stays legible without a forced walk.
sub OpenSettingEditor(stepId as String)
    HideSettingsMenu()
    full = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-_:/"
    prefill = ""
    titleText = ""
    msgText = ""
    if stepId = "febbox" then
        m.settingsStep = "febbox"
        prefill = m.cfg.febboxToken
        titleText = "Step 1 of 3 - Febbox token (free)"
        msgText = "Step 1 of 3: paste your Febbox token so streams can play. Get one at febbox.com with a fresh Google account, copy it from browser storage or network requests, then type it here."
    else if stepId = "provider" then
        m.settingsStep = "provider"
        prefill = m.cfg.providerApiBase
        titleText = "Step 2 of 3 - Provider URL (optional)"
        msgText = "Step 2 of 3: only needed if you run your own providers-api worker. Paste its base URL such as https colon slash slash your-worker.workers.dev. Leave empty and press DONE to skip."
    else if stepId = "tmdb" then
        m.settingsStep = "tmdb"
        prefill = m.cfg.tmdbKey
        titleText = "Step 3 of 3 - TMDB key"
        msgText = "Step 3 of 3: free read-only TMDB key for browsing and search. Get one at themoviedb.org/settings/api, then paste it here."
    end if
    ShowKeyDialog(titleText, msgText, prefill, full)
end sub

sub ShowKeyDialog(title as String, msg as String, prefill as String, charset as String)
    if m.settingsDialog <> invalid then
        CleanupChild(m.settingsDialog)
        m.settingsDialog = invalid
    end if
    dialog = CreateObject("roSGNode", "Keypad")
    dialog.title = title
    dialog.message = msg + "  •  DONE saves and returns to settings  •  BACK discards"
    if charset <> "" and charset <> invalid then
        dialog.charset = charset
    end if
    if prefill <> "" and prefill <> invalid then
        dialog.text = prefill
    end if
    dialog.observeField("wasAccepted", "OnKeyDialogAccepted")
    dialog.observeField("wasCancelled", "OnKeyDialogCancelled")
    m.settingsDialog = dialog
    m.top.appendChild(dialog)
    grid = dialog.findNode("keysGrid")
    if grid <> invalid then
        grid.setFocus(true)
    else
        dialog.setFocus(true)
    end if
    ? "KEYPAD settings opened step=" + m.settingsStep
end sub

sub OnKeyDialogAccepted(msg as Object)
    dialog = m.settingsDialog
    value = ""
    if dialog <> invalid then
        value = dialog.text
        ' Same invalid-text guard as OnSearchAccepted: the provider step has
        ' an empty prefill, so DONE would store invalid into the registry and
        ' crash later string concats (Bearer header / scrape URL).
        ' https://developer.roku.com/dev/docs/expressions-variables-types (Invalid type)
        if value = invalid then value = ""
        CleanupChild(dialog)
    end if
    m.settingsDialog = invalid

    if m.settingsStep = "febbox" then
        m.cfg.febboxToken = value
        ConfigSave(m.cfg)
    else if m.settingsStep = "provider" then
        m.cfg.providerApiBase = value
        ConfigSave(m.cfg)
    else if m.settingsStep = "tmdb" then
        if value <> "" then
            m.cfg.tmdbKey = value
            ConfigSave(m.cfg)
        end if
    end if
    m.settingsStep = ""
    ShowToast("Settings saved.")
    ' Reopen the menu with fresh states: BACK or Done from an editor returns
    ' here instead of being dumped straight to the rows.
    ShowSettingsMenu()
end sub

sub OnKeyDialogCancelled(msg as Object)
    ' BACK from an editor returns to the settings menu without saving; the
    ' menu then shows fresh states so the user can pick another step.
    CleanupChild(m.settingsDialog)
    m.settingsDialog = invalid
    m.settingsStep = ""
    ShowSettingsMenu()
end sub

sub CloseSettings()
    HideSettingsMenu()
    ConfigSave(m.cfg)
    PersistDrain()
    m.statusLabel.text = "OK opens details  •  PLAY plays featured  •  SEARCH finds titles"
    RestoreDetailsFocus()
end sub

' ------------------------------------------------------------------
' Key handling + helpers
' ------------------------------------------------------------------

' ------------------------------------------------------------------
' User profiles (picker, add/rename/delete, switching)
' ------------------------------------------------------------------

function IsModalOpen() as Boolean
    if m.profilePickerGroup <> invalid then return true
    if m.profileDialog <> invalid then return true
    if m.searchDialog <> invalid then return true
    if m.settingsDialog <> invalid then return true
    if m.settingsMenuGroup <> invalid then return true
    if m.detailsGroup <> invalid then return true
    if m.sourcePickerGroup <> invalid then return true
    if m.progressGroup <> invalid then return true
    if m.seriesScene <> invalid then return true
    if m.liveTvScene <> invalid then return true
    if m.playback <> invalid then return true
    if m.genreGroup <> invalid then return true
    return false
end function

' Avatar strip for the profile picker: procedural colored-initial tiles
' (Rectangle + Label, zero new files, zero licensing risk). Decorative only —
' key focus stays on the LabelList below, so focus discipline is unchanged.
' Active profile gets a white edge so "current user" reads at a glance.
sub BuildProfileAvatarStrip(g as Object)
    if g = invalid then return
    if m.profiles = invalid then return
    total = m.profiles.profiles.count()
    if total <= 0 then return
    if total > 4 then total = 4
    slotW = 168
    gap = 28
    stripW = total * slotW + (total - 1) * gap
    startX = 960 - stripW \ 2
    baseY = 352
    activeId = ProfilesGetActiveId(m.profiles)
    for i = 0 to total - 1
        p = m.profiles.profiles[i]
        nm = ProfilesStr(p, "name", "Profile")
        pid = ProfilesStr(p, "id", "")
        hex = ProfilesAvatarHex(ProfilesAvatarIndex(m.profiles, pid))
        baseX = startX + i * (slotW + gap)
        if pid <> "" and pid = activeId then
            glow = CreateObject("roSGNode", "Rectangle")
            glow.color = "0xD4202866"
            glow.width = slotW + 20
            glow.height = slotW + 20
            glow.translation = [baseX - 10, baseY - 10]
            g.appendChild(glow)
            edge = CreateObject("roSGNode", "Rectangle")
            edge.color = "0xFFFFFFFF"
            edge.width = slotW + 10
            edge.height = slotW + 10
            edge.translation = [baseX - 5, baseY - 5]
            g.appendChild(edge)
        end if
        tile = CreateObject("roSGNode", "Rectangle")
        tile.color = hex
        tile.width = slotW
        tile.height = slotW
        tile.translation = [baseX, baseY]
        g.appendChild(tile)
        tileEdge = CreateObject("roSGNode", "Rectangle")
        tileEdge.color = "0x00000066"
        tileEdge.width = slotW
        tileEdge.height = 6
        tileEdge.translation = [baseX, baseY + slotW - 6]
        g.appendChild(tileEdge)
        face = CreateObject("roSGNode", "Label")
        face.text = ProfilesAvatarInitial(nm)
        face.font = "font:LargeBoldSystemFont"
        face.color = "0xFFFFFFFF"
        face.width = slotW
        face.height = 110
        face.translation = [baseX, baseY + 24]
        face.horizAlign = "center"
        face.vertAlign = "center"
        g.appendChild(face)
        ' Real avatar art over the procedural tile: covers it when loaded,
        ' transparent while loading or offline so the initial tile shows through.
        art = CreateObject("roSGNode", "Poster")
        art.uri = ProfilesAvatarUrl(m.profiles, pid)
        art.loadDisplayMode = "scaleToFill"
        art.width = slotW
        art.height = slotW
        art.translation = [baseX, baseY]
        g.appendChild(art)
        cap = CreateObject("roSGNode", "Label")
        cap.text = nm
        cap.font = "font:MediumSystemFont"
        cap.color = "0xFFFFFFFF"
        cap.width = slotW + 20
        cap.height = 32
        cap.translation = [baseX - 10, baseY + slotW + 8]
        cap.horizAlign = "center"
        cap.vertAlign = "center"
        cap.wrap = true
        cap.maxLines = 1
        g.appendChild(cap)
    end for
end sub

sub ShowProfilePicker(mode as String)
    try
        ShowProfilePickerReal(mode)
        if m.bootGroup <> invalid then
            m.bootPickerDone = true
            BootStage("boot 3/4: picker ready")
            BootStageDone()
        end if
    catch e
        ShowFatalError("profile picker", e)
    end try
end sub

sub ShowProfilePickerReal(mode as String)
    if m.profilePickerGroup <> invalid then return
    m.profilePickerMode = mode
    m.profiles = ProfilesLoad()
    m.lastProfileId = ""

    g = CreateObject("roSGNode", "Rectangle")
    g.color = "0x000000FF"
    g.width = 1920
    g.height = 1080
    g.translation = "[0,0]"
    m.profilePickerGroup = g

    card = CreateObject("roSGNode", "Rectangle")
    card.color = "0x0B0E17F5"
    card.width = 760
    card.height = 640
    card.translation = "[580,240]"
    g.appendChild(card)

    cardAccent = CreateObject("roSGNode", "Rectangle")
    cardAccent.color = "0xD42028FF"
    cardAccent.width = 760
    cardAccent.height = 4
    cardAccent.translation = "[580,236]"
    g.appendChild(cardAccent)

    title = CreateObject("roSGNode", "Label")
    title.text = "WHO'S WATCHING?"
    title.font = "font:MediumBoldSystemFont"
    title.color = "0xF5F5F5FF"
    title.translation = "[620,272]"
    title.width = 680
    title.height = 48
    title.horizAlign = "center"
    title.vertAlign = "center"
    g.appendChild(title)

    hint = CreateObject("roSGNode", "Label")
    if m.profiles <> invalid and m.profiles.profiles.count() = 0 then
        hint.text = "No profiles yet - pick + ADD PROFILE below"
    else
        hint.text = "Pick a profile  •  Up to 4"
    end if
    hint.font = "font:SmallSystemFont"
    hint.color = "0x9CA3AFFF"
    hint.translation = "[620,324]"
    hint.width = 680
    hint.height = 30
    hint.horizAlign = "center"
    hint.vertAlign = "center"
    hint.wrap = true
    hint.maxLines = 1
    g.appendChild(hint)

    BuildProfileAvatarStrip(g)

    m.profileItems = []
    content = CreateObject("roSGNode", "ContentNode")
    activeId = ProfilesGetActiveId(m.profiles)
    for each p in m.profiles.profiles
        pid = ProfilesStr(p, "id", "")
        label = ProfilesStr(p, "name", "Profile")
        if pid <> "" and pid = activeId then
            label = label + "  (active)"
        end if
        if pid <> "" then
            savedCount = ProfilesWatchlistGet(m.profiles, pid).count()
            if savedCount > 0 then
                label = label + "  •  " + savedCount.ToStr() + " saved"
            end if
        end if
        nd = content.createChild("ContentNode")
        nd.title = label
        m.profileItems.Push({ kind: "profile", id: pid })
    end for
    if m.profiles.profiles.count() < 4 then
        nd = content.createChild("ContentNode")
        nd.title = "+ ADD PROFILE"
        m.profileItems.Push({ kind: "add" })
    end if
    if mode = "manage" and activeId <> "" then
        nd = content.createChild("ContentNode")
        nd.title = "RENAME CURRENT PROFILE"
        m.profileItems.Push({ kind: "rename" })
        nd = content.createChild("ContentNode")
        nd.title = "NEXT AVATAR"
        m.profileItems.Push({ kind: "avatar" })
        nd = content.createChild("ContentNode")
        nd.title = "DELETE CURRENT PROFILE"
        m.profileItems.Push({ kind: "delete" })
    end if

    list = CreateObject("roSGNode", "LabelList")
    list.content = content
    list.itemSize = "[640,60]"
    list.numRows = 4
    list.translation = "[640,576]"
    list.focusBitmapUri = "pkg:/images/btn_focus.png"
    list.focusFootprintBitmapUri = "pkg:/images/btn_footprint.png"
    list.color = "0x9CA3AFFF"
    list.focusedColor = "0xFFFFFFFF"
    list.observeField("itemSelected", "OnProfilePicked")
    list.observeField("itemFocused", "OnProfileFocused")
    g.appendChild(list)
    m.profileList = list

    profHint = CreateObject("roSGNode", "Label")
    ' Short Medium hint: LargeBold overflowed the 680px card line.
    profHint.text = "OK selects  •  BACK goes home"
    profHint.font = "font:MediumSystemFont"
    profHint.color = "0xE5E7EBFF"
    profHint.translation = "[640,832]"
    profHint.width = 680
    profHint.height = 48
    profHint.horizAlign = "center"
    profHint.vertAlign = "center"
    g.appendChild(profHint)

    m.top.appendChild(g)
    HomeFadeIn(g)
    list.setFocus(true)
    ? "PROFILES picker opened mode=" + mode + " count=" + m.profiles.profiles.count().ToStr()
end sub

sub HideProfilePicker()
    StopHomeFade()
    CleanupChild(m.profilePickerGroup)
    m.profilePickerGroup = invalid
    m.profileList = invalid
    m.profileItems = []
end sub

sub FocusProfileList()
    if m.profilePickerGroup <> invalid and m.profileList <> invalid then
        m.profileList.setFocus(true)
    else
        m.rows.setFocus(true)
    end if
end sub

sub AfterProfileChosen()
    ' try/catch + status breadcrumbs: the target TV's debug console streams
    ' no prints, so if this chain ever dies again the status bar must say
    ' where (each step below overwrites the previous breadcrumb; the final
    ' "Profile: X active!" only appears when the whole chain survived).
    try
        nm = ProfilesGetActiveName(m.profiles)
        HideProfilePicker()
        m.statusLabel.text = "Saving profile..."
        PersistDrain()
        m.statusLabel.text = "Rebuilding rows..."
        if m.homeNext >= m.homeRowDefs.count() then
            BuildHomeRows()
        end if
        if nm <> "" then
            m.statusLabel.text = "Profile: " + nm
            ShowToast("Profile '" + nm + "' active!")
        end if
        if not IsModalOpen() then
            m.rows.setFocus(true)
        end if
        MaybeProcessLaunch()
    catch e
        m.statusLabel.text = "PROFILE ERR: " + HomeErrorText(e)
    end try
end sub

' Exception-object text for the on-screen error trap (this device's console
' is blind; e.Message may also be missing/invalid on this firmware).
function HomeErrorText(e as Dynamic) as String
    if e <> invalid and type(e) = "roAssociativeArray" and e.DoesExist("Message") then
        msg = e["Message"]
        if msg <> invalid and (type(msg) = "String" or type(msg) = "roString") and msg <> "" then
            return msg
        end if
    end if
    return "unexpected error"
end function

sub OnProfileFocused(msg as Object)
    if m.profileList = invalid then return
    index = m.profileList.itemFocused
    if index = invalid or index < 0 or index >= m.profileItems.count() then return
    item = m.profileItems[index]
    if item.kind = "profile" then
        m.lastProfileId = item.id
    end if
end sub

sub OnProfilePicked(msg as Object)
    if m.profileList = invalid then return
    index = m.profileList.itemSelected
    if index = invalid or index < 0 or index >= m.profileItems.count() then return
    item = m.profileItems[index]
    kind = item.kind
    ? "PROFILES picked kind=" + kind
    if kind = "profile" then
        if ProfilesSetActive(m.profiles, item.id) then
            AfterProfileChosen()
        end if
    else if kind = "add" then
        ShowProfileNameDialog("add", "")
    else if kind = "rename" then
        ShowProfileNameDialog("rename", ProfilesGetActiveName(m.profiles))
    else if kind = "avatar" then
        avatarId = ""
        if m.lastProfileId <> invalid and m.lastProfileId <> "" then avatarId = m.lastProfileId
        if avatarId = "" and m.profileList <> invalid then
            ci = m.profileList.itemSelected
            if ci <> invalid and ci >= 0 and ci < m.profileItems.count() then
                it = m.profileItems[ci]
                if it.kind = "profile" then avatarId = it.id
            end if
        end if
        if avatarId = "" then avatarId = ProfilesGetActiveId(m.profiles)
        if avatarId <> "" then
            ProfilesCycleAvatarStyle(m.profiles, avatarId)
            PersistDrain()
            keepMode = m.profilePickerMode
            HideProfilePicker()
            ShowProfilePicker(keepMode)
            ShowToast("Avatar updated.")
        else
            FocusProfileList()
        end if
    else if kind = "delete" then
        delId = ProfilesGetActiveId(m.profiles)
        if delId <> "" and ProfilesDelete(m.profiles, delId) then
            PersistDrain()
            ShowToast("Profile deleted.")
        end if
        mode = m.profilePickerMode
        HideProfilePicker()
        ShowProfilePicker(mode)
    end if
end sub

sub ShowProfileNameDialog(mode as String, prefill as String)
    if m.profileDialog <> invalid then return
    m.profileNameMode = mode
    dialog = CreateObject("roSGNode", "Keypad")
    if mode = "rename" then
        dialog.title = "Rename profile"
    else
        dialog.title = "New profile"
    end if
    dialog.message = "Type a name, then DONE. CANCEL goes back without saving."
    dialog.charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    dialog.searchMode = false
    if prefill <> "" and prefill <> invalid then
        dialog.text = prefill
    end if
    dialog.observeField("wasAccepted", "OnProfileNameAccepted")
    dialog.observeField("wasCancelled", "OnProfileNameCancelled")
    m.profileDialog = dialog
    m.top.appendChild(dialog)
    grid = dialog.findNode("keysGrid")
    if grid <> invalid then
        grid.setFocus(true)
    else
        dialog.setFocus(true)
    end if
    ? "KEYPAD profile name opened mode=" + mode
end sub

sub OnProfileNameAccepted(msg as Object)
    dialog = m.profileDialog
    value = ""
    if dialog <> invalid then
        value = dialog.text
        if value = invalid then value = ""
        CleanupChild(dialog)
    end if
    m.profileDialog = invalid
    mode = m.profileNameMode
    m.profileNameMode = ""
    if mode = "add" then
        try
            if value.Trim() = "" then
                value = "Profile " + (m.profiles.profiles.count() + 1).ToStr()
            end if
            m.statusLabel.text = "Creating profile..."
            id = ProfilesCreate(m.profiles, value)
            if id <> invalid then
                m.statusLabel.text = "Activating profile..."
                ProfilesSetActive(m.profiles, id)
                AfterProfileChosen()
            else
                m.statusLabel.text = "Maximum of 4 profiles."
                FocusProfileList()
            end if
        catch e
            ' Blind-console device: show the failure where it can be read.
            m.statusLabel.text = "PROFILE ERR: " + HomeErrorText(e)
        end try
    else if mode = "rename" then
        if value.Trim() <> "" then
            ProfilesRename(m.profiles, ProfilesGetActiveId(m.profiles), value)
        end if
        keep = m.profilePickerMode
        HideProfilePicker()
        ShowProfilePicker(keep)
    else
        FocusProfileList()
    end if
end sub

sub OnProfileNameCancelled(msg as Object)
    CleanupChild(m.profileDialog)
    m.profileDialog = invalid
    m.profileNameMode = ""
    FocusProfileList()
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

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then
        return false
    end if
    if key = "play" then
        if IsModalOpen() then return false
        if m.heroRec <> invalid and SafeStr(m.heroRec, "tmdbId", "") <> "" then
            if SafeStr(m.heroRec, "mediaType", "movie") = "tv" then
                ShowSeriesDetails(m.heroRec)
            else
                ShowDetails(m.heroRec)
            end if
            return true
        end if
        return false
    end if
    if key = "options" then
        ' * (options) = quick watchlist toggle (audit + user request): works
        ' on the details overlay (any title) and on focused home tiles
        ' (movies AND tv). Genuinely modal overlays block it; the details
        ' overlay deliberately does NOT (that is where the selected record
        ' lives). SeriesDetailScene handles its own * while focused.
        if m.profilePickerGroup <> invalid or m.profileDialog <> invalid then return false
        if m.searchDialog <> invalid or m.settingsDialog <> invalid or m.settingsMenuGroup <> invalid then return false
        if m.sourcePickerGroup <> invalid or m.progressGroup <> invalid then return false
        if m.liveTvScene <> invalid or m.seriesScene <> invalid or m.playback <> invalid then return false
        if m.genreGroup <> invalid then return false
        if RailHasFocus() then return false
        return HomeOptionsQuickWatchlist()
    end if
    if key = "left" then
        ' Rail entry: LEFT at the rows' first column hands focus to the
        ' shortcut rail. Guarded to rows-focus only, so nested scenes
        ' (Live TV, Series, Playback) keep their own LEFT behavior.
        if m.rows <> invalid and m.rows.hasFocus() and not m.inSearch and not IsModalOpen() then
            if m.focusedCol <= 0 and m.railList <> invalid then
                m.railList.setFocus(true)
                return true
            end if
        end if
        return false
    end if
    if key = "right" then
        if RailHasFocus() then
            if m.rows <> invalid then m.rows.setFocus(true)
            return true
        end if
        return false
    end if
    if key = "back" then
        ' Rail is chrome, not modal: BACK simply returns focus to the rows.
        if RailHasFocus() then
            if m.rows <> invalid then m.rows.setFocus(true)
            return true
        end if
        ' Profile picker is modal. In manage mode Back closes it; at startup
        ' Back is swallowed until a profile is picked (or one is already
        ' active) so home content stays blocked. The Home button still exits.
        if m.profileDialog <> invalid then
            return false
        end if
        if m.profilePickerGroup <> invalid then
            if key = "left" or key = "right" then
                if m.profileList <> invalid then
                    ci = m.profileList.itemSelected
                    if ci <> invalid and ci >= 0 and ci < m.profileItems.count() then
                        it = m.profileItems[ci]
                        if it.kind = "profile" and it.id <> "" then
                            ProfilesCycleAvatarStyle(m.profiles, it.id)
                            PersistDrain()
                            keepMode = m.profilePickerMode
                            HideProfilePicker()
                            ShowProfilePicker(keepMode)
                            ShowToast("Avatar updated.")
                            return true
                        end if
                    end if
                end if
            end if
            if m.profilePickerMode = "manage" then
                HideProfilePicker()
                m.rows.setFocus(true)
                return true
            end if
            if ProfilesGetActiveId(m.profiles) <> "" then
                AfterProfileChosen()
                return true
            end if
            return true
        end if
        ' Progress modal is modal: cancel the fetch first. Otherwise Back
        ' would close the details screen underneath, stranding the popup over
        ' the home rows and letting the next OK open a second details page
        ' ON TOP of the popup (z-order break + apparent misplacement).
        if m.progressGroup <> invalid then
            CancelProgress()
            return true
        end if
        if m.sourcePickerGroup <> invalid then
            StopHomeFade()
            CleanupChild(m.sourcePickerGroup)
            m.sourcePickerGroup = invalid
            m.sourceList = invalid
            m.pendingCandidates = invalid
            RestoreDetailsFocus()
            return true
        end if
        if m.trailerScene <> invalid then
            ' BACK inside the trailer player: the scene signals "done" and
            ' TrailerDone does the teardown, but a BACK that arrives while
            ' the observer is not running still has to land here.
            CleanupChild(m.trailerScene)
            m.trailerScene = invalid
            m.rows.setFocus(true)
            return true
        end if
        if m.trailerTask <> invalid then
            ' A lookup still in flight: abandon it rather than let it open a
            ' player over the home screen.
            TrailerStopTask()
            m.rows.setFocus(true)
            return true
        end if
        if m.seriesScene <> invalid then
            CleanupChild(m.seriesScene)
            m.seriesScene = invalid
            m.rows.setFocus(true)
            return true
        end if
        if m.liveTvScene <> invalid then
            CleanupChild(m.liveTvScene)
            m.liveTvScene = invalid
            m.rows.setFocus(true)
            return true
        end if
        ' Genre browse screen is modal: Back closes it and returns to rows.
        if m.genreGroup <> invalid then
            CloseGenreScreen()
            m.rows.setFocus(true)
            return true
        end if
        ' Same safety net for search: if focus escaped the Keypad dialog (its
        ' own Back handler then never fires), Back here still closes search so
        ' the user can never get stranded under the overlay.
        if m.searchDialog <> invalid then
            CleanupChild(m.searchDialog)
            m.searchDialog = invalid
            m.rows.setFocus(true)
            return true
        end if
        ' Settings menu is modal: Back closes it and restores details/rows.
        if m.settingsMenuGroup <> invalid then
            CloseSettings()
            return true
        end if
        ' Safety net for the settings Keypad editor: Back reopens the menu it
        ' came from instead of dumping the user to the rows.
        if m.settingsDialog <> invalid then
            CleanupChild(m.settingsDialog)
            m.settingsDialog = invalid
            m.settingsStep = ""
            ShowSettingsMenu()
            return true
        end if
        if m.detailsGroup <> invalid then
            CloseDetails()
            return true
        end if
        if m.inSearch then
            m.statusLabel.text = ""
            LoadHomeRows()
            return true
        end if
    end if
    return false
end function
