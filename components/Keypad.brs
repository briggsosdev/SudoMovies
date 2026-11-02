sub init()
    m.titleLabel = m.top.findNode("titleLabel")
    m.msgLabel = m.top.findNode("msgLabel")
    m.echo = m.top.findNode("echoLabel")
    m.echoBorder = m.top.findNode("echoBorder")
    m.echoBox = m.top.findNode("echoBox")
    m.headerBar = m.top.findNode("headerBar")
    m.headerAccent = m.top.findNode("headerAccent")
    m.grid = m.top.findNode("keysGrid")
    m.resultsLabel = m.top.findNode("resultsLabel")
    m.resultsEmpty = m.top.findNode("resultsEmptyLabel")
    m.resultsPanel = m.top.findNode("resultsPanel")
    m.resultsAccent = m.top.findNode("resultsAccent")
    m.resultsGrid = m.top.findNode("resultsGrid")
    m.timer = m.top.findNode("searchTimer")
    m.keyIdx = 0
    m.resIdx = 0
    m.pendingTask = invalid
    m.searchBusy = false
    m.searchRetry = false
    m.resultMovies = []
    m.top.observeField("title", "OnPadTitle")
    m.top.observeField("message", "OnPadMessage")
    m.top.observeField("text", "OnPadText")
    m.top.observeField("charset", "OnPadRebuild")
    m.top.observeField("searchMode", "OnPadRebuild")
    m.grid.observeField("itemSelected", "OnKeySelected")
    m.grid.observeField("itemFocused", "OnKeyFocused")
    m.resultsGrid.observeField("itemSelected", "OnResultPicked")
    m.resultsGrid.observeField("itemFocused", "OnResFocused")
    m.timer.observeField("fire", "OnSearchTimerFire")
    OnPadTitle(invalid)
    OnPadMessage(invalid)
    OnPadText(invalid)
    RefreshAll(invalid)
end sub

sub OnPadTitle(msg as Object)
    if m.top.title <> invalid then
        m.titleLabel.text = m.top.title
    end if
end sub

sub OnPadMessage(msg as Object)
    if m.top.message <> invalid then
        m.msgLabel.text = m.top.message
    end if
end sub

sub OnPadText(msg as Object)
    t = m.top.text
    if t = invalid then
        t = ""
    end if
    if t = "" then
        m.echo.text = "Type a title..._"
        m.echo.color = "0x6B7280FF"
    else
        m.echo.text = t + "_"
        m.echo.color = "0xFFFFFFFF"
    end if
end sub

sub OnPadRebuild(msg as Object)
    RefreshAll(invalid)
end sub

sub RefreshAll(msg as Object)
    ApplyMode()
    BuildKeys()
end sub

sub ApplyMode()
    search = (m.top.searchMode = true)
    ' ONE centered compact keyboard for both modes (entry + search):
    ' 8 cols x [120,100] keys + 10px gaps = 1030 wide, centered at x=445;
    ' 5 rows = 540 tall at y=360 (below the echo box, clear of the bottom).
    ' 36 charset keys + SPACE/DEL/DONE/CANCEL fill 8x5 exactly. The old
    ' entry-mode 190x120 keys were oversized and off-center.
    m.grid.translation = "[445,360]"
    m.grid.itemSize = [120, 100]
    m.grid.itemSpacing = [10, 10]
    m.grid.numColumns = 8
    m.grid.numRows = 5
    if search then
        ' Keyboard (entry) state: keyboard chrome shown, full-screen feed
        ' geometry pre-staged on the hidden results nodes so there is only
        ' ONE results geometry in the whole component (no side/full mismatch).
        m.grid.visible = true
        SetKeyboardChromeVisible(true)
        SetFeedVisible(false)
        ApplyFeedGeometry()
    else
        SetKeyboardChromeVisible(true)
        SetFeedVisible(false)
    end if
end sub

sub SetKeyboardChromeVisible(v as Boolean)
    echoGlow = m.top.findNode("echoGlow")
    echoEdge = m.top.findNode("echoEdge")
    sideBar = m.top.findNode("headerSideBar")
    for each n in [m.titleLabel, m.msgLabel, m.echo, m.echoBorder, m.echoBox, echoGlow, echoEdge, sideBar, m.headerBar, m.headerAccent]
        if n <> invalid then
            n.visible = v
        end if
    end for
    if m.grid <> invalid then
        m.grid.visible = v
    end if
end sub

sub SetFeedVisible(v as Boolean)
    edge = m.top.findNode("resultsEdge")
    if edge <> invalid then
        edge.visible = v
    end if
    if m.resultsPanel <> invalid then
        m.resultsPanel.visible = v
    end if
    if m.resultsAccent <> invalid then
        m.resultsAccent.visible = v
    end if
    if m.resultsLabel <> invalid then
        m.resultsLabel.visible = v
    end if
    if m.resultsGrid <> invalid then
        m.resultsGrid.visible = v
    end if
    UpdateResultsEmpty()
end sub

' Empty state for the full-screen feed: visible only while the feed is open
' and the live search has nothing to show (e.g. text cleared mid-browse).
sub UpdateResultsEmpty()
    if m.resultsEmpty = invalid then return
    showFeed = false
    if m.resultsPanel <> invalid and m.resultsPanel.visible = true then
        showFeed = true
    end if
    noneFound = true
    if m.resultMovies <> invalid then
        if m.resultMovies.count() > 0 then noneFound = false
    end if
    m.resultsEmpty.visible = showFeed and noneFound
end sub

' Scannable 10-foot tile line shared by live results: year plus rating plus
' media badge so movies and shows read instantly apart. Runtime TMDB data
' only, zero bundle.
function KeypadTileLine(rec as Object) as String
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

sub ApplyFeedGeometry()
    ' Single source of truth for the full-screen centered feed.
    ' Panel [60,60] 1800x960 -> x center 60+900=960, y center 60+480=540.
    ' Grid [84,144] 6 x [282,360] + 5 x 12 = 1752 wide -> 84+876=960.
    ' Grid height 2 x 360 + 12 = 732 -> 144..876, inside panel 60..1020.
    if m.resultsPanel <> invalid then
        m.resultsPanel.translation = "[60,60]"
        m.resultsPanel.width = 1800
        m.resultsPanel.height = 956
    end if
    if m.resultsAccent <> invalid then
        m.resultsAccent.translation = "[60,60]"
        m.resultsAccent.width = 1800
        m.resultsAccent.height = 4
    end if
    if m.resultsLabel <> invalid then
        m.resultsLabel.translation = "[84,84]"
        m.resultsLabel.width = 1752
        m.resultsLabel.height = 40
    end if
    if m.resultsGrid <> invalid then
        m.resultsGrid.translation = "[84,144]"
        m.resultsGrid.itemSize = [282, 360]
        m.resultsGrid.itemSpacing = [12, 12]
        m.resultsGrid.numColumns = 6
        m.resultsGrid.numRows = 2
    end if
end sub

sub BuildKeys()
    chars = m.top.charset
    if chars = invalid or chars = "" then
        chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    end if
    cols = m.grid.numColumns
    if cols = invalid or cols <= 0 then
        cols = 9
    end if
    content = CreateObject("roSGNode", "ContentNode")
    for i = 1 to chars.Len()
        ch = chars.Mid(i - 1, 1)
        nd = content.createChild("ContentNode")
        nd.title = ch
    end for
    for each k in ["SPACE", "DEL", "DONE", "CANCEL"]
        nd = content.createChild("ContentNode")
        nd.title = k
    end for
    extras = content.getChildCount() MOD cols
    if extras > 0 then
        for i = extras to cols - 1
            nd = content.createChild("ContentNode")
            nd.title = ""
        end for
    end if
    m.keyIdx = 0
    m.grid.content = content
    OnPadText(invalid)
end sub

sub OnKeyFocused(msg as Object)
    idx = msg.getData()
    if idx <> invalid then
        m.keyIdx = idx
    end if
end sub

sub OnResFocused(msg as Object)
    idx = msg.getData()
    if idx <> invalid then
        m.resIdx = idx
    end if
end sub

sub OnKeySelected(msg as Object)
    idx = msg.getData()
    if idx = invalid then
        return
    end if
    child = m.grid.content.getChild(idx)
    if child = invalid then
        return
    end if
    k = child.title
    ? "KEYPAD key=" + k
    if k = "DONE" then
        m.top.wasAccepted = true
    else if k = "CANCEL" then
        m.top.wasCancelled = true
    else if k = "DEL" then
        t = m.top.text
        if t = invalid then
            t = ""
        end if
        if t.Len() > 0 then
            m.top.text = t.Left(t.Len() - 1)
        end if
        QueueLiveSearch()
    else if k = "SPACE" then
        t = m.top.text
        if t = invalid then
            t = ""
        end if
        m.top.text = t + " "
        QueueLiveSearch()
    else if k <> "" and k <> invalid then
        t = m.top.text
        if t = invalid then
            t = ""
        end if
        m.top.text = t + k
        QueueLiveSearch()
    end if
end sub

sub QueueLiveSearch()
    if m.top.searchMode <> true then
        return
    end if
    t = m.top.text
    if t = invalid then
        t = ""
    end if
    if t = "" then
        m.resultMovies = []
        m.resultsGrid.content = CreateObject("roSGNode", "ContentNode")
        if m.resultsLabel <> invalid then m.resultsLabel.text = "RESULTS"
        UpdateResultsEmpty()
        return
    end if
    m.timer.control = "stop"
    m.timer.control = "start"
end sub

sub OnSearchTimerFire(msg as Object)
    t = m.top.text
    if t = invalid or t = "" then
        return
    end if
    key = m.top.tmdbKey
    if key = invalid or key = "" then
        return
    end if
    if m.searchBusy then
        m.searchRetry = true
        return
    end if
    m.searchBusy = true
    m.searchRetry = false
    task = CreateObject("roSGNode", "ApiTask")
    task.url = TmdbSearchUrl({}, t)
    task.headers = TmdbHeaders(key)
    task.observeField("raw", "OnLiveResponse")
    m.pendingTask = task
    task.control = "run"
    ? "KEYPAD livesearch q=" + t
end sub

sub OnLiveResponse(msg as Object)
    if msg = invalid then
        return
    end if
    raw = msg.getData()
    st = 0
    if m.pendingTask <> invalid then
        st = m.pendingTask.status
    end if
    m.pendingTask = invalid
    m.searchBusy = false
    if m.searchRetry then
        m.searchRetry = false
        QueueLiveSearch()
        return
    end if
    if st <> 200 then
        return
    end if
    if raw = invalid or raw = "" then
        return
    end if
    movies = TmdbParseMovies(raw)
    shown = []
    for i = 0 to movies.count() - 1
        if i >= 12 then
            exit for
        end if
        shown.Push(movies[i])
    end for
    m.resultMovies = shown
    content = CreateObject("roSGNode", "ContentNode")
    for each rec in shown
        nd = content.createChild("ContentNode")
        nd.HDPosterUrl = rec.poster
        nd.title = rec.title
        nd.shortDescriptionLine1 = KeypadTileLine(rec)
        chipText = SafeStr(rec, "rating", "")
        if chipText <> "" then
            nd.addField("chip", "string", false)
            nd.chip = chipText
        end if
    end for
    m.resIdx = 0
    m.resultsGrid.content = content
    ' Focus race guard: if the user already jumped into the feed (keyboard
    ' hidden) when this late response lands, replacing .content drops focus
    ' to nowhere and the remote goes dead. Re-assert feed focus.
    if m.grid <> invalid and m.grid.visible = false and m.resultsGrid.visible = true then
        m.resultsGrid.setFocus(true)
    end if
    if m.resultsLabel <> invalid then
        q = m.top.text
        if q = invalid then q = ""
        shortQ = q
        if shortQ.Len() > 20 then shortQ = shortQ.Left(20) + "..."
        if shown.count() = 0 then
            if shortQ = "" then
                m.resultsLabel.text = "NO MATCHES YET - KEEP TYPING"
            else
                m.resultsLabel.text = "NO MATCHES for " + Chr(34) + shortQ + Chr(34) + " - KEEP TYPING"
            end if
        else
            if shortQ = "" then
                m.resultsLabel.text = "RESULTS (" + shown.count().ToStr() + ") - RIGHT browses  •  OK picks"
            else
                m.resultsLabel.text = "RESULTS (" + shown.count().ToStr() + ") for " + Chr(34) + shortQ + Chr(34) + " - RIGHT browses"
            end if
        end if
    end if
    UpdateResultsEmpty()
    ? "KEYPAD liveresults=" + shown.count().ToStr()
end sub

sub OnResultPicked(msg as Object)
    idx = msg.getData()
    if idx = invalid or m.resultMovies = invalid then
        return
    end if
    if idx < 0 or idx >= m.resultMovies.count() then
        return
    end if
    m.top.picked = m.resultMovies[idx]
    m.top.wasPicked = true
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then
        return false
    end if
    if key = "back" then
        ' Stop the in-flight live-search fetch (audit finding): the dialog
        ' closes via wasCancelled, but an orphaned task kept the detached
        ' scene alive until completion for nothing.
        if m.pendingTask <> invalid then
            m.pendingTask.control = "stop"
            m.pendingTask = invalid
        end if
        m.top.wasCancelled = true
        return true
    end if
    if m.top.searchMode = true then
        if key = "right" and m.grid.hasFocus() and m.grid.visible = true then
            cols = m.grid.numColumns
            if cols > 0 and (m.keyIdx MOD cols) = cols - 1 then
                if m.resultMovies <> invalid and m.resultMovies.count() > 0 then
                    HideKeyboardForFeed()
                    m.resultsGrid.setFocus(true)
                    return true
                end if
            end if
        else if key = "left" and m.resultsGrid.hasFocus() then
            rcols = m.resultsGrid.numColumns
            if rcols = invalid or rcols <= 0 then
                rcols = 6
            end if
            if (m.resIdx MOD rcols) = 0 then
                RestoreKeyboardForEntry()
                m.grid.setFocus(true)
                return true
            end if
        end if
    end if
    return false
end function

sub HideKeyboardForFeed()
    if m.grid = invalid then
        return
    end if
    if m.grid.visible = false then
        return
    end if
    ' Full-screen centered feed: hide ALL keyboard chrome (keys + echo +
    ' header) so the opaque panel never half-covers the echo box, then show
    ' the single centered feed geometry. See ApplyFeedGeometry for math.
    SetKeyboardChromeVisible(false)
    ApplyFeedGeometry()
    SetFeedVisible(true)
end sub

sub RestoreKeyboardForEntry()
    if m.grid = invalid then
        return
    end if
    SetFeedVisible(false)
    m.grid.translation = "[445,360]"
    m.grid.itemSize = [120, 100]
    m.grid.itemSpacing = [10, 10]
    m.grid.numColumns = 8
    m.grid.numRows = 5
    SetKeyboardChromeVisible(true)
    RestoreResultsPos()
end sub

sub RestoreResultsPos()
    ' Legacy name kept for callers; keyboard state keeps the feed hidden,
    ' but the geometry stays the single centered feed geometry so a later
    ' HideKeyboardForFeed() shows identical layout (no side/full mismatch).
    ApplyFeedGeometry()
    SetFeedVisible(false)
end sub
