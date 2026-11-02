' GenreBrowser: genre chips + paged poster grid + PREV/NEXT page buttons.
'
' DESIGN (read this before changing it): this component owns focus ITSELF and
' handles every key in onKeyEvent. There are no List/Grid nodes to hand focus
' between, so there is no edge-bubbling, no *Selected observer and no
' itemHasFocus/focusPercent behaviour to depend on. Everything on screen is a
' plain Rectangle / Poster / Label created below and repainted from three
' pieces of state:
'     m.zone       "tabs" | "grid" | "pager"      which row has focus
'     m.tabFocus   chip under the cursor          (m.tabIdx = loaded genre)
'     m.gridFocus  poster under the cursor        (0..19)
'     m.pageFocus  0 = PREV, 2 = NEXT
'
' KEY NAMES: the remote's OK button arrives as "OK" (not "select"), rewind
' as "rev" and fast-forward as "fwd". The old version tested key = "select",
' which can never be true, so nothing was ever selectable.
'
' FOCUS: a Group is NOT focusable by default. Because every visible node here
' is a plain Rectangle/Poster/Label, init MUST set m.top.focusable = true
' before any setFocus call, or the home screen behind keeps the remote and
' this screen looks frozen.

sub init()
    m.heading = m.top.findNode("heading")
    m.statusLabel = m.top.findNode("statusLabel")
    m.arrowL = m.top.findNode("arrowL")
    m.arrowR = m.top.findNode("arrowR")
    m.chipLayer = m.top.findNode("chipLayer")
    m.gridLayer = m.top.findNode("gridLayer")
    m.pagerLayer = m.top.findNode("pagerLayer")
    m.tabTimer = m.top.findNode("tabTimer")

    ' CRITICAL: everything on this screen is a plain Rectangle / Poster /
    ' Label, and a Group is NOT focusable by default. Without this line
    ' m.top.setFocus(true) silently does nothing, the home screen behind
    ' keeps the remote, and this screen looks frozen: OK re-opens the
    ' browser on ACTION, LEFT/RIGHT never move a highlight, and PREV/NEXT
    ' can't be reached. LiveTvScene hit the identical bug. Must be set
    ' before the first setFocus call.
    m.top.focusable = true

    m.CHIP_W = 180
    m.CHIP_H = 44
    m.CHIP_STEP = 190
    m.CHIP_VIS = 9
    m.COLS = 10
    m.CELLS = 20
    m.CELL_W = 168
    m.POSTER_H = 252
    m.STEP_X = 180
    m.STEP_Y = 324

    m.movies = []
    m.task = invalid
    m.closed = false
    m.started = false
    m.page = 1
    m.pages = 1
    m.total = 0
    m.loading = false
    m.pendingPage = 1
    m.tabIdx = 0
    m.tabFocus = 0
    m.gridFocus = 0
    m.pageFocus = 2
    m.zone = "tabs"
    m.wantGrid = false

    m.tabs = GenreTabs()
    BuildChips()
    BuildCells()
    BuildPager()

    ' Chip scrolling is debounced so holding LEFT/RIGHT does not fire a
    ' TMDB request per key-repeat. The highlight still moves instantly.
    m.tabTimer.observeField("fire", "OnTabTimer")
    m.top.observeField("start", "OnStart")

    PaintHeading()
    m.statusLabel.text = "Loading " + TabName() + "..."
    RenderAll()
end sub

sub OnStart(msg as Object)
    if m.closed then return
    if m.started then return
    m.started = true
    idx = 0
    gid = m.top.genreId
    if gid <> invalid and gid <> "" then idx = TabIndexForGenre(gid)
    m.tabFocus = idx
    ' Attached to the scene by now, so this focus request actually lands.
    m.top.setFocus(true)
    SelectTab(idx)
end sub

function GenreTabs() as Object
    return [
        { label: "ACTION", gid: "28" },
        { label: "COMEDY", gid: "35" },
        { label: "DRAMA", gid: "18" },
        { label: "HORROR", gid: "27" },
        { label: "SCI-FI", gid: "878" },
        { label: "THRILLER", gid: "53" },
        { label: "ROMANCE", gid: "10749" },
        { label: "ANIMATION", gid: "16" },
        { label: "ADVENTURE", gid: "12" },
        { label: "FANTASY", gid: "14" },
        { label: "MYSTERY", gid: "9648" },
        { label: "CRIME", gid: "80" },
        { label: "FAMILY", gid: "10751" },
        { label: "DOCUMENTARY", gid: "99" },
        { label: "WAR", gid: "10752" },
        { label: "WESTERN", gid: "37" },
        { label: "MUSIC", gid: "10402" },
        { label: "HISTORY", gid: "36" }
    ]
end function

function TabIndexForGenre(gid as String) as Integer
    for i = 0 to m.tabs.count() - 1
        if m.tabs[i].gid = gid then return i
    end for
    return 0
end function

function TabName() as String
    if m.tabs = invalid or m.tabs.count() = 0 then return "Genres"
    return m.tabs[m.tabIdx].label
end function

sub PaintHeading()
    if m.heading = invalid then return
    m.heading.text = TabName()
end sub

function TabUrl(tabDef as Object, page as Integer) as String
    return "discover/movie?with_genres=" + tabDef.gid + "&page=" + page.ToStr() + "&sort_by=popularity.desc&include_adult=false&vote_count.gte=50"
end function

' ---------------------------------------------------------- node helpers

function GbRect(parent as Object, x as Integer, y as Integer, w as Integer, h as Integer, clr as String) as Object
    r = CreateObject("roSGNode", "Rectangle")
    r.translation = [x, y]
    r.width = w
    r.height = h
    r.color = clr
    parent.appendChild(r)
    return r
end function

function GbLabel(parent as Object, x as Integer, y as Integer, w as Integer, h as Integer, txt as String, fnt as String, clr as String) as Object
    l = CreateObject("roSGNode", "Label")
    l.translation = [x, y]
    l.width = w
    l.height = h
    l.font = fnt
    l.color = clr
    l.text = txt
    l.maxLines = 1
    parent.appendChild(l)
    return l
end function

' ------------------------------------------------------------------ build

sub BuildChips()
    m.chipRect = []
    m.chipLbl = []
    for i = 0 to m.tabs.count() - 1
        r = GbRect(m.chipLayer, 0, 0, m.CHIP_W, m.CHIP_H, "0x1B2233FF")
        l = GbLabel(m.chipLayer, 0, 0, m.CHIP_W, m.CHIP_H, m.tabs[i].label, "font:SmallBoldSystemFont", "0xB0B8C8FF")
        l.horizAlign = "center"
        l.vertAlign = "center"
        m.chipRect.Push(r)
        m.chipLbl.Push(l)
    end for
end sub

sub BuildCells()
    ' NOTE: named cellNodes, not cells. BrightScript identifiers are
    ' CASE-INSENSITIVE, so m.cells and the m.CELLS count were the same key:
    ' assigning the array overwrote 20, and "for i = 0 to m.CELLS - 1" threw
    ' a Type Mismatch inside init(), crashing the channel on open.
    m.cellNodes = []
    for i = 0 to m.CELLS - 1
        col = i MOD m.COLS
        row = i \ m.COLS
        x = col * m.STEP_X
        y = row * m.STEP_Y
        ring = GbRect(m.gridLayer, x - 5, y - 5, m.CELL_W + 10, m.POSTER_H + 10, "0xFFFFFFFF")
        ring.visible = false
        poster = CreateObject("roSGNode", "Poster")
        poster.translation = [x, y]
        poster.width = m.CELL_W
        poster.height = m.POSTER_H
        poster.loadDisplayMode = "scaleToFit"
        poster.visible = false
        m.gridLayer.appendChild(poster)
        ttl = GbLabel(m.gridLayer, x, y + m.POSTER_H + 4, m.CELL_W, 28, "", "font:SmallBoldSystemFont", "0xF5F5F5FF")
        yr = GbLabel(m.gridLayer, x, y + m.POSTER_H + 32, m.CELL_W, 22, "", "font:SmallestSystemFont", "0x9CA3AFFF")
        m.cellNodes.Push({ ring: ring, poster: poster, title: ttl, year: yr })
    end for
end sub

sub BuildPager()
    m.pagerRect = []
    m.pagerLbl = []
    labels = ["< PREV", "PAGE 1 / 1", "NEXT >"]
    for i = 0 to 2
        x = i * 216
        r = GbRect(m.pagerLayer, x, 0, 200, 44, "0x141A28FF")
        l = GbLabel(m.pagerLayer, x, 0, 200, 44, labels[i], "font:SmallBoldSystemFont", "0x7C869BFF")
        l.horizAlign = "center"
        l.vertAlign = "center"
        m.pagerRect.Push(r)
        m.pagerLbl.Push(l)
    end for
end sub

' ----------------------------------------------------------------- render

sub RenderAll()
    RenderTabs()
    RenderGrid()
    RenderPager()
end sub

sub RenderTabs()
    n = m.tabs.count()
    start = m.tabFocus - 4
    if start > n - m.CHIP_VIS then start = n - m.CHIP_VIS
    if start < 0 then start = 0
    for i = 0 to n - 1
        r = m.chipRect[i]
        l = m.chipLbl[i]
        vis = (i >= start and i < start + m.CHIP_VIS)
        r.visible = vis
        l.visible = vis
        if vis then
            x = (i - start) * m.CHIP_STEP
            r.translation = [x, 0]
            l.translation = [x, 0]
            if m.zone = "tabs" and i = m.tabFocus then
                r.color = "0xD42028FF"
                l.color = "0xFFFFFFFF"
            else if i = m.tabIdx then
                r.color = "0x8B1A1FFF"
                l.color = "0xFFFFFFFF"
            else
                r.color = "0x1B2233FF"
                l.color = "0xB0B8C8FF"
            end if
        end if
    end for
    m.arrowL.visible = (start > 0)
    m.arrowR.visible = (start + m.CHIP_VIS < n)
end sub

' Repaint cell CONTENT (poster/title/year) after a page load.
sub FillCells()
    for i = 0 to m.cellNodes.count() - 1
        c = m.cellNodes[i]
        if i < m.movies.count() then
            rec = m.movies[i]
            p = rec.poster
            if p = invalid or p = "" then p = "pkg:/images/poster_placeholder.png"
            c.poster.uri = p
            c.title.text = rec.title
            c.year.text = rec.year
            c.poster.visible = true
            c.title.visible = true
            c.year.visible = true
        else
            c.poster.visible = false
            c.title.visible = false
            c.year.visible = false
            c.ring.visible = false
        end if
    end for
end sub

' Repaint cell FOCUS only.
sub RenderGrid()
    for i = 0 to m.cellNodes.count() - 1
        c = m.cellNodes[i]
        if i < m.movies.count() then
            focused = (m.zone = "grid" and i = m.gridFocus)
            c.ring.visible = focused
            if focused then
                c.title.color = "0xFFFFFFFF"
            else
                c.title.color = "0xB0B8C8FF"
            end if
        end if
    end for
end sub

sub RenderPager()
    prevOn = (m.page > 1)
    nextOn = (m.page < m.pages)
    m.pagerLbl[1].text = "PAGE " + m.page.ToStr() + " / " + m.pages.ToStr()
    m.pagerRect[1].color = "0x0A0E17FF"
    m.pagerLbl[1].color = "0x8B95A8FF"
    PaintPagerButton(0, prevOn)
    PaintPagerButton(2, nextOn)
end sub

sub PaintPagerButton(idx as Integer, enabled as Boolean)
    r = m.pagerRect[idx]
    l = m.pagerLbl[idx]
    focused = (m.zone = "pager" and m.pageFocus = idx)
    if not enabled then
        if focused then
            r.color = "0x2A3350FF"
        else
            r.color = "0x141A28FF"
        end if
        l.color = "0x7C869BFF"
    else if focused then
        r.color = "0xD42028FF"
        l.color = "0xFFFFFFFF"
    else
        r.color = "0x1B2233FF"
        l.color = "0xB0B8C8FF"
    end if
end sub

' -------------------------------------------------------------- selection

' Move the chip highlight right away; load the genre once the user stops.
sub QueueTab(idx as Integer)
    n = m.tabs.count()
    if idx < 0 then idx = n - 1
    if idx >= n then idx = 0
    m.tabFocus = idx
    m.tabTimer.control = "stop"
    if idx <> m.tabIdx then m.tabTimer.control = "start"
    RenderTabs()
end sub

sub OnTabTimer()
    if m.closed then return
    if m.tabFocus <> m.tabIdx then SelectTab(m.tabFocus)
end sub

sub SelectTab(idx as Integer)
    if m.closed then return
    m.tabTimer.control = "stop"
    n = m.tabs.count()
    if idx < 0 then idx = 0
    if idx >= n then idx = n - 1
    m.tabIdx = idx
    m.tabFocus = idx
    PaintHeading()
    StopTask()
    m.page = 1
    m.pages = 1
    m.total = 0
    m.movies = []
    m.gridFocus = 0
    FillCells()
    FetchPage(1)
    RenderAll()
end sub

sub PageStep(delta as Integer)
    if m.loading then return
    target = m.page + delta
    if target < 1 or target > m.pages then return
    FetchPage(target)
end sub

' ------------------------------------------------------------------ fetch

sub FetchPage(page as Integer)
    if m.closed then return
    if page < 1 then return
    StopTask()
    m.loading = true
    m.pendingPage = page
    m.statusLabel.text = "Loading " + TabName() + " - page " + page.ToStr() + "..."
    key = ""
    setKey = m.top.tmdbKey
    if setKey <> invalid and setKey <> "" then key = setKey
    if key = "" then key = AppConstants().tmdbDefaultKey
    task = CreateObject("roSGNode", "ApiTask")
    if task = invalid then
        m.loading = false
        return
    end if
    task.url = TmdbDiscoverUrl({}, TabUrl(m.tabs[m.tabIdx], page))
    task.headers = TmdbHeaders(key)
    task.observeField("raw", "OnGenreResponse")
    m.task = task
    task.control = "run"
end sub

sub StopTask()
    if m.task <> invalid then
        m.task.unobserveField("raw")
        m.task.control = "stop"
        m.task = invalid
    end if
    m.loading = false
end sub

sub OnGenreResponse(evt as Object)
    if m.task = invalid then return
    src = evt.getRoSGNode()
    if src = invalid then return
    if not src.isSameNode(m.task) then return
    m.task = invalid
    m.loading = false
    if m.closed then return
    body = src.raw
    if src.status <> 200 or body = invalid or body = "" then
        m.statusLabel.text = "Couldn't load " + TabName() + ". Try another genre, or BACK."
        RenderAll()
        return
    end if
    ' Bad/short JSON must degrade to a message, not throw out of an observer
    ' callback (which shows a modal error and reads as a freeze).
    try
        ApplyResults(body)
    catch e
        ? "GENRE parse error: " + e
        m.movies = []
        m.total = 0
        FillCells()
        m.statusLabel.text = "Couldn't read the results for " + TabName() + ". Try another genre."
        RenderAll()
    end try
end sub

sub ApplyResults(body as String)
    got = TmdbParseMovies(body)
    m.page = m.pendingPage
    m.pages = TmdbTotalPages(body)
    ' TMDB serves at most 500 pages.
    if m.pages > 500 then m.pages = 500
    if m.page > m.pages then m.pages = m.page
    if got.count() > m.CELLS then
        trimmed = []
        for i = 0 to m.CELLS - 1
            trimmed.Push(got[i])
        end for
        got = trimmed
    end if
    m.movies = got
    m.total = got.count()
    m.gridFocus = 0
    FillCells()
    if m.total = 0 then
        m.statusLabel.text = "No titles found for " + TabName() + "."
    else
        m.statusLabel.text = m.total.ToStr() + " titles  -  " + TabName() + "  -  page " + m.page.ToStr() + " of " + m.pages.ToStr()
    end if
    ' DOWN was pressed while the genre was still loading: honour it now.
    if m.wantGrid and m.total > 0 and m.zone = "tabs" then
        m.zone = "grid"
    end if
    m.wantGrid = false
    ' Paging from the page bar with a now-empty/short result: keep focus legal.
    if m.zone = "grid" and m.total = 0 then m.zone = "tabs"
    RenderAll()
end sub

' ------------------------------------------------------------------- keys

sub CloseBrowser()
    m.closed = true
    m.tabTimer.control = "stop"
    StopTask()
    m.top.done = true
end sub

sub EnterPager()
    m.zone = "pager"
    if m.page < m.pages then
        m.pageFocus = 2
    else
        m.pageFocus = 0
    end if
end sub

function KeyTabs(key as String) as Boolean
    if key = "left" then
        QueueTab(m.tabFocus - 1)
        return true
    else if key = "right" then
        QueueTab(m.tabFocus + 1)
        return true
    else if key = "OK" then
        SelectTab(m.tabFocus)
        return true
    else if key = "down" then
        if m.tabFocus <> m.tabIdx then SelectTab(m.tabFocus)
        if m.total > 0 then
            m.zone = "grid"
        else
            m.wantGrid = true
        end if
        return true
    else if key = "up" then
        return true
    end if
    return false
end function

function KeyGrid(key as String) as Boolean
    g = m.gridFocus
    cnt = m.movies.count()
    col = g MOD m.COLS
    row = g \ m.COLS
    if key = "left" then
        if col > 0 then
            m.gridFocus = g - 1
        else
            ' LEFT off the first column hands focus back to the genre strip
            ' (it sits directly above). UP on the top row does the same.
            m.zone = "tabs"
        end if
        return true
    else if key = "right" then
        if col < m.COLS - 1 and g + 1 < cnt then m.gridFocus = g + 1
        return true
    else if key = "up" then
        if row > 0 then
            m.gridFocus = g - m.COLS
        else
            m.zone = "tabs"
        end if
        return true
    else if key = "down" then
        if g + m.COLS < cnt then
            m.gridFocus = g + m.COLS
        else
            EnterPager()
        end if
        return true
    else if key = "OK" then
        if g >= 0 and g < cnt then m.top.picked = m.movies[g]
        return true
    end if
    return false
end function

function KeyPager(key as String) as Boolean
    if key = "left" then
        m.pageFocus = 0
        return true
    else if key = "right" then
        m.pageFocus = 2
        return true
    else if key = "up" then
        if m.movies.count() > 0 then
            m.zone = "grid"
            if m.gridFocus >= m.movies.count() then m.gridFocus = m.movies.count() - 1
        else
            m.zone = "tabs"
        end if
        return true
    else if key = "down" then
        return true
    else if key = "OK" then
        if m.pageFocus = 0 then
            PageStep(-1)
        else
            PageStep(1)
        end if
        return true
    end if
    return false
end function

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if m.closed then return false
    ' A runtime error thrown out of a key handler becomes a modal BrightScript
    ' error dialog - the app looks frozen with no way back. Never let one out.
    try
        return HandleKey(key)
    catch e
        ? "GENRE key error (" + key + "): " + e
        if key = "back" then
            CloseBrowser()
            return true
        end if
        return false
    end try
end function

function HandleKey(key as String) as Boolean
    if key = "back" then
        CloseBrowser()
        return true
    end if
    if key <> "down" then m.wantGrid = false

    handled = false
    if key = "fwd" then
        PageStep(1)
        handled = true
    else if key = "rev" then
        PageStep(-1)
        handled = true
    else if m.zone = "tabs" then
        handled = KeyTabs(key)
    else if m.zone = "grid" then
        handled = KeyGrid(key)
    else if m.zone = "pager" then
        handled = KeyPager(key)
    end if
    if handled then RenderAll()
    return handled
end function
