' ------------------------------------------------------------------
' LIVE GRID (cable-style time grid)
' ------------------------------------------------------------------
' A "dumb view" module: LiveTvScene owns the state AA (m.liveTvGridState)
' and the container node, and forwards keys here. No focusable nodes, no
' observers - the scene's onKeyEvent drives everything, which is why the
' grid can be opened from the rail without fighting the LabelList focus.
'
' Layout math (all constants in one place):
'   gutter (channel names)  36..336      time area  344..1884
'   ruler 158..214          rows start 214, 10 rows of 76px
'   window = 120 minutes    -> 12.83 px per minute
'
' Performance shape (the reason this is its own file):
'   - Vertical scroll rebuilds only the ~10 visible rows (virtualized), so
'     100+ channels are never all in the tree.
'   - Horizontal scroll does NOT rebuild: it only rewrites translation/width
'     on the blocks that already exist, which is what makes time paging feel
'     instant on this hardware.
' ------------------------------------------------------------------

function LiveTvGridLayout() as Object
    lay = {}
    lay.x0 = 36
    lay.y0 = 158
    lay.gutterW = 300
    lay.rulerH = 56
    lay.rowH = 76
    lay.rows = 10
    lay.timeX = 344
    lay.timeW = 1540
    lay.spanMin = 120
    lay.pxPerMin = 12.8333
    ' Opaque body height, shared by the backdrop, the gutter panel and the
    ' gutter edge. These were three separate literals (852 / 856 / 856), so
    ' the gutter and its red edge hung 4px below the backdrop that is supposed
    ' to be covering the scene. One value, so they cannot drift again.
    lay.bodyH = 852
    lay.bodyY = 158
    return lay
end function

' Full grid view. rows/blocks/nowLine are created here; the scene hides
' browseGroup while this is up.
' Round an epoch DOWN to the nearest half hour, so a guide window always
' starts on :00 or :30 the way a printed cable guide does.
function LiveTvGridSnapHalfHour(epoch as Integer) as Integer
    if epoch = invalid then return 0
    if epoch <= 0 then return 0
    return Int(epoch / 1800) * 1800
end function

sub LiveTvGridBuild(st as Object, root as Object, channels as Object, epg as Object, nowSec as Integer)
    if st = invalid or root = invalid then return
    lay = LiveTvGridLayout()
    st.layout = lay
    st.channels = channels
    st.epg = epg
    st.focus = 0
    st.first = 0
    st.blocks = []
    st.rows = []
    st.withProgs = 0
    if nowSec <= 0 then nowSec = LiveTvNowSec()
    st.now = nowSec
    ' Open on "now" with a little runway to the left, like a real grid, and
    ' snapped DOWN to a half hour so the gridlines and the ruler labels agree
    ' with each other instead of the columns drifting off the hour marks.
    st.winStart = LiveTvGridSnapHalfHour(nowSec - Int(30 * 60))

    ' Opaque backdrop: this node is the topmost child while the grid is up.
    bg = CreateObject("roSGNode", "Rectangle")
    bg.color = "0x05070DFF"
    bg.width = 1920
    bg.height = lay.bodyH
    bg.translation = "[0," + lay.bodyY.ToStr() + "]"
    root.appendChild(bg)

    ' Channel-name gutter panel.
    gut = CreateObject("roSGNode", "Rectangle")
    gut.color = "0x0B0E17F5"
    gut.width = lay.gutterW
    gut.height = lay.bodyH
    gut.translation = "[" + lay.x0.ToStr() + "," + lay.bodyY.ToStr() + "]"
    root.appendChild(gut)
    gutEdge = CreateObject("roSGNode", "Rectangle")
    gutEdge.color = "0xD42028FF"
    gutEdge.width = 6
    gutEdge.height = lay.bodyH
    gutEdge.translation = "[" + lay.x0.ToStr() + "," + lay.bodyY.ToStr() + "]"
    root.appendChild(gutEdge)

    ' Time ruler: one label per half hour across the window.
    st.rulerLabels = []
    st.rulerTicks = []
    head = CreateObject("roSGNode", "Group")
    root.appendChild(head)
    i = 0
    while i < 5
        lx = lay.timeX + Int(i * lay.timeW / 4)
        tick = CreateObject("roSGNode", "Rectangle")
        tick.color = "0x1F2937FF"
        tick.width = 2
        tick.height = 12
        tick.translation = "[" + lx.ToStr() + "," + (lay.y0 + lay.rulerH - 12).ToStr() + "]"
        head.appendChild(tick)
        st.rulerTicks.Push(tick)
        lb = CreateObject("roSGNode", "Label")
        lb.color = "0xE5E7EBFF"
        lb.font = "font:MediumBoldSystemFont"
        lb.width = 150
        lb.height = 34
        ' RIGHT-EDGE LABEL CLIPPING. All five boxes used to start AT their
        ' column and run 150px to the right, so the last one began at
        ' timeX+timeW = 1884 and ended at 2034 - 114px past the 1920px screen,
        ' i.e. the +2:00 stamp was sliced in half or gone entirely. The last
        ' label now ENDS on its column. The first four stay left-aligned:
        ' shifting them left instead would push them back into the gutter.
        if i = 4 then
            lb.horizAlign = "right"
            lb.translation = "[" + (lx - 150).ToStr() + ",166]"
        else
            lb.translation = "[" + lx.ToStr() + ",166]"
        end if
        head.appendChild(lb)
        st.rulerLabels.Push(lb)
        i = i + 1
    end while

    ' "NOW" playhead nodes are created AFTER rowsRoot below, so they paint
    ' over the programme blocks instead of being hidden beneath them.

    ' Hint strip at the bottom of the grid (replaces the info panel area).
    hint = CreateObject("roSGNode", "Label")
    hint.color = "0x9CA3AFFF"
    hint.font = "font:SmallSystemFont"
    hint.width = 1840
    hint.height = 30
    hint.translation = "[48,978]"
    hint.text = "Up/Down channel  -  Left/Right page time  -  OK watch  -  BACK exit grid"
    root.appendChild(hint)

    st.rowsRoot = CreateObject("roSGNode", "Group")
    root.appendChild(st.rowsRoot)

    ' "NOW" playhead: appended AFTER rowsRoot so it composites above the
    ' programme blocks. Moved, not rebuilt, on every time scroll.
    st.nowLine = CreateObject("roSGNode", "Rectangle")
    st.nowLine.color = "0xD42028FF"
    st.nowLine.width = 4
    st.nowLine.height = lay.rows * lay.rowH
    st.nowLine.translation = "[" + lay.timeX.ToStr() + "," + (lay.y0 + lay.rulerH).ToStr() + "]"
    root.appendChild(st.nowLine)
    st.nowPillBg = CreateObject("roSGNode", "Rectangle")
    st.nowPillBg.color = "0xD42028FF"
    st.nowPillBg.width = 70
    st.nowPillBg.height = 26
    root.appendChild(st.nowPillBg)
    st.nowPill = CreateObject("roSGNode", "Label")
    st.nowPill.color = "0xFFFFFFFF"
    st.nowPill.font = "font:SmallBoldSystemFont"
    st.nowPill.width = 70
    st.nowPill.height = 26
    st.nowPill.text = "NOW"
    st.nowPill.horizAlign = "center"
    st.nowPill.vertAlign = "center"
    root.appendChild(st.nowPill)

    ' Half-hour gridlines BEHIND the rows. A cable guide reads as a grid
    ' because the columns are visible through the programme blocks; without
    ' them the rows look like a flat stack of coloured bars. Appended before
    ' any row so row backgrounds and blocks paint over them.
    st.colsRoot = CreateObject("roSGNode", "Group")
    st.rowsRoot.appendChild(st.colsRoot)
    st.colLines = []
    ci = 0
    while ci <= 5
        cl = CreateObject("roSGNode", "Rectangle")
        cl.color = "0xFFFFFF14"
        cl.width = 1
        cl.height = lay.rows * lay.rowH
        cl.visible = false
        st.colsRoot.appendChild(cl)
        st.colLines.Push(cl)
        ci = ci + 1
    end while

    ' Header: what this screen is, on the left, wall clock on the right. This
    ' sits in the scene's top bar (0..150) above the grid body, which starts
    ' at y0=158 - so it is kept at y>=104 to clear the "LIVE TV" title
    ' (y=34..104) and above topAccent at y=145.
    hdr = CreateObject("roSGNode", "Label")
    hdr.color = "0xFFFFFFFF"
    hdr.font = "font:MediumBoldSystemFont"
    hdr.width = 900
    hdr.height = 40
    hdr.vertAlign = "center"
    hdr.translation = "[" + lay.x0.ToStr() + ",104]"
    hdr.text = "LIVE GUIDE"
    root.appendChild(hdr)
    st.clock = CreateObject("roSGNode", "Label")
    st.clock.color = "0xFFD75EFF"
    st.clock.font = "font:MediumBoldSystemFont"
    st.clock.width = 260
    st.clock.height = 38
    st.clock.horizAlign = "right"
    st.clock.vertAlign = "center"
    st.clock.translation = "[" + (lay.timeX + lay.timeW - 260).ToStr() + ",106]"
    root.appendChild(st.clock)

    LiveTvGridRuler(st)
    LiveTvGridRenderRows(st)
end sub

' Hour/half-hour labels for the current window.
' Index-guarded: st.rulerLabels is emptied by LiveTvGridClear and is only
' refilled by LiveTvGridBuild, so any Ruler call that lands in between (a key
' or clock tick arriving during teardown) used to index an empty array, which
' throws and pops a modal error dialog over the grid.
' Put the half-hour gridlines on REAL half-hour boundaries inside the
' current window, not at fixed fractions of it. Paging time by an odd number
' of minutes would otherwise slide the columns off the hour marks and the grid
' stops reading as a timetable. A fixed pool is reused and hidden, so a scroll
' never allocates nodes.
sub LiveTvGridColumns(st as Object)
    if st = invalid then return
    lay = st.layout
    if lay = invalid then return
    if st.colLines = invalid then return
    n = st.colLines.count()
    if n = 0 then return
    ' First half-hour boundary at or after the left edge of the window.
    k = Int(st.winStart / 1800)
    if k * 1800 < st.winStart then k = k + 1
    used = 0
    while used < n
        t = k * 1800 + used * 1800
        x = lay.timeX + Int((t - st.winStart) / 60.0 * lay.pxPerMin)
        cl = st.colLines[used]
        if cl <> invalid then
            if x > lay.timeX + 2 and x < lay.timeX + lay.timeW then
                cl.visible = true
                cl.translation = "[" + x.ToStr() + ",0]"
            else
                cl.visible = false
            end if
        end if
        used = used + 1
    end while
end sub

sub LiveTvGridRuler(st as Object)
    if st = invalid then return
    lay = st.layout
    if lay = invalid then return
    ' Columns and the wall clock are positioned independently of the label
    ' pool, so they update even while the labels are being torn down.
    LiveTvGridColumns(st)
    if st.clock <> invalid then
        st.clock.text = LiveTvClockOfDay(st.now)
    end if
    if st.rulerLabels = invalid then return
    spanSec = Int(lay.spanMin * 60)
    tickSec = Int(spanSec / 4)
    n = st.rulerLabels.count()
    if n = 0 then return
    i = 0
    while i < 5 and i < n
        t = st.winStart + i * tickSec
        lb = st.rulerLabels[i]
        if lb <> invalid then lb.text = LiveTvClockOfDay(t)
        i = i + 1
    end while
end sub

' Rebuild only the visible window of rows. Called on vertical scroll and on
' data changes, never on horizontal scroll.
sub LiveTvGridRenderRows(st as Object)
    if st = invalid then return
    ' rowsRoot and layout only exist once LiveTvGridBuild has run. A key or
    ' tick that arrives between LiveTvGridClear and the rebuild would
    ' otherwise dereference invalid and throw a modal error.
    if st.rowsRoot = invalid or st.layout = invalid then return
    lay = st.layout
    chans = st.channels
    if chans = invalid then chans = []
    total = chans.count()
    st.first = LiveTvGridClampFirst(st, st.focus)
    ' Wipe the previous rows. Every node a row created is a SIBLING under
    ' rowsRoot (the row background has no children), so removal has to walk
    ' the tracked node list - reading r.bg.getChildren() removed nothing and
    ' leaked the whole grid on every scroll.
    prev = st.rows
    for each r in prev
        if r.nodes <> invalid then
            for each n in r.nodes
                if n <> invalid then
                    st.rowsRoot.removeChild(n)
                end if
            end for
        end if
    end for
    st.rows = []
    st.blocks = []
    i = 0
    while i < lay.rows
        chIdx = st.first + i
        if chIdx >= total then exit while
        y = lay.y0 + lay.rulerH + i * lay.rowH
        row = LiveTvGridBuildRow(st, chans[chIdx], chIdx, y)
        st.rows.Push(row)
        i = i + 1
    end while
    LiveTvGridTimePositions(st)
    LiveTvGridPaintFocus(st)
    ' withProgs is the diagnostic that matters: how many visible rows resolved
    ' a real schedule. If it is 0 while blocks = rows, every row took the
    ' always-on channel-name fallback.
    withProgs = 0
    for each r in st.rows
        if r.progCount > 0 then withProgs = withProgs + 1
    end for
    st.withProgs = withProgs
    st.lastRowNow = st.now
    ? "GRID render first=" + st.first.ToStr() + " focus=" + st.focus.ToStr() + " rows=" + st.rows.count().ToStr() + " blocks=" + st.blocks.count().ToStr() + " withProgs=" + withProgs.ToStr()
end sub

function LiveTvGridBuildRow(st as Object, ch as Object, chIdx as Integer, y as Integer) as Object
    lay = st.layout
    row = {}
    row.chIdx = chIdx
    row.ch = ch
    row.y = y
    row.isFocus = (chIdx = st.focus)
    ' Collect every node this row appends so LiveTvGridRenderRows can remove
    ' exactly these on the next render.
    nodes = []
    st.buildNodes = nodes
    bg = CreateObject("roSGNode", "Rectangle")
    if row.isFocus then
        bg.color = "0x1E293BFF"
    else if (chIdx mod 2) = 0 then
        bg.color = "0x0D1320FF"
    else
        bg.color = "0x0A0F19FF"
    end if
    bg.width = lay.gutterW + lay.timeW
    bg.height = lay.rowH - 8
    bg.translation = "[" + lay.x0.ToStr() + "," + y.ToStr() + "]"
    st.rowsRoot.appendChild(bg)
    nodes.Push(bg)
    row.bg = bg

    ' Gutter: channel number badge + name. The number sits on a filled plate
    ' like a cable guide's channel column, and the focused row gets a red bar
    ' down the left edge (added here, toggled by LiveTvGridPaintFocus).
    fb = CreateObject("roSGNode", "Rectangle")
    fb.color = "0xD42028FF"
    fb.width = 5
    fb.height = lay.rowH - 8
    fb.translation = "[" + lay.x0.ToStr() + "," + y.ToStr() + "]"
    fb.visible = row.isFocus
    st.rowsRoot.appendChild(fb)
    nodes.Push(fb)
    row.focusBar = fb

    numBg = CreateObject("roSGNode", "Rectangle")
    if row.isFocus then
        numBg.color = "0xD42028FF"
    else
        numBg.color = "0x1F2937FF"
    end if
    numBg.width = 52
    numBg.height = 34
    numBg.translation = "[" + (lay.x0 + 14).ToStr() + "," + (y + 13).ToStr() + "]"
    st.rowsRoot.appendChild(numBg)
    nodes.Push(numBg)
    row.numBg = numBg

    num = CreateObject("roSGNode", "Label")
    if row.isFocus then
        num.color = "0xFFFFFFFF"
    else
        num.color = "0x9CA3AFFF"
    end if
    num.font = "font:MediumBoldSystemFont"
    num.width = 52
    num.height = 34
    num.horizAlign = "center"
    num.vertAlign = "center"
    num.translation = "[" + (lay.x0 + 14).ToStr() + "," + (y + 13).ToStr() + "]"
    ' THE RECORD KEY IS "chNo", NOT "chno". LiveTvParseChannels writes
    ' chNo (LiveTv.brs), the curated renumber writes chNo (LiveTvTask.brs,
    ' `curated[i].chNo = i + 1`), the cache-serve renumber writes chNo, and
    ' every reader in this app - LiveTvChanNoText, the type-ahead numeric
    ' entry, the grid - reads chNo. The feed's own lowercase "chno" is
    ' consumed inside the parser and never stored. This used to look up
    ' "chno" first and only then "chNo", which always missed on the first
    ' key and fell through to the second: the badges came out right by
    ' accident, but the comment recorded a field name that does not exist in
    ' the record, so the next reader who trusted it broke the grid again.
    ' Primary chNo, legacy chno as a fallback for any record that still
    ' carries the old spelling, row index as the last resort.
    cno = SafeStr(ch, "chNo", "")
    if cno = "" then cno = SafeStr(ch, "chno", "")
    if cno = "" then cno = (chIdx + 1).ToStr()
    num.text = cno
    st.rowsRoot.appendChild(num)
    nodes.Push(num)
    row.num = num

    nm = CreateObject("roSGNode", "Label")
    nm.color = "0xFFFFFFFF"
    nm.font = "font:MediumSystemFont"
    nm.width = lay.gutterW - 84
    nm.height = 40
    nm.translation = "[" + (lay.x0 + 78).ToStr() + "," + (y + 10).ToStr() + "]"
    nm.text = LiveTvGridChanName(ch)
    st.rowsRoot.appendChild(nm)
    nodes.Push(nm)
    row.name = nm

    ' Vertical hairline between gutter and timeline.
    sep = CreateObject("roSGNode", "Rectangle")
    sep.color = "0x1F2937FF"
    sep.width = 2
    sep.height = lay.rowH - 8
    sep.translation = "[" + (lay.x0 + lay.gutterW).ToStr() + "," + y.ToStr() + "]"
    st.rowsRoot.appendChild(sep)
    nodes.Push(sep)

    ' Program blocks from the EPG.
    progs = LiveTvGridPrograms(st, ch)
    ' How many blocks this row's schedule can actually produce. Kept on the row
    ' so LiveTvGridRenderRows can report it: blocks=rows is ambiguous (a real
    ' schedule and the always-on fallback both produce one block per row),
    ' and that ambiguity is why a grid stuck on the fallback read as a data
    ' problem instead of a lookup problem.
    row.progCount = progs.count()
    ' Hard cap per row. A guide that returns hundreds of overlapping entries
    ' for one channel (bad chno mapping, duplicated XMLTV blocks) used to
    ' build a node per entry, which is the classic way a scene grinds to a
    ' halt on this hardware.
    maxBlocks = 24
    if progs.count() = 0 then
        ' Premium/sudo rows have no schedule grid: show the item as an
        ' always-on block so the row is never a dead empty strip.
        LiveTvGridAddBlock(st, chIdx, st.winStart, st.winStart + Int(lay.spanMin * 60), LiveTvGridChanName(ch), "ondemand", false)
    else
        made = 0
        for each p in progs
            if made < maxBlocks then
                pStart = LiveTvToInt(SafeGet(p, "start", 0))
                pStop = LiveTvToInt(SafeGet(p, "stop", 0))
                if pStart > 0 and pStop > pStart then
                    LiveTvGridAddBlock(st, chIdx, pStart, pStop, LiveTvProgTitle(p), "prog", pStart <= st.now and st.now < pStop)
                    made = made + 1
                end if
            end if
        end for
    end if
    st.buildNodes = invalid
    row.nodes = nodes
    return row
end function

function LiveTvGridChanName(ch as Object) as String
    nm = SafeStr(ch, "title", "Channel")
    if nm = "" then nm = "Channel"
    return nm
end function

' Programs overlapping the visible window (plus a margin so blocks are
' already built when the user pages time).
function LiveTvGridPrograms(st as Object, ch as Object) as Object
    out = []
    progs = LiveTvGridProgramList(st, ch)
    if type(progs) <> "roArray" then return out
    lay = st.layout
    from = st.winStart - 1800
    toSec = st.winStart + Int(lay.spanMin * 60) + 1800
    for each p in progs
        if type(p) = "roAssociativeArray" then
            pStart = LiveTvToInt(SafeGet(p, "start", 0))
            pStop = LiveTvToInt(SafeGet(p, "stop", 0))
            if pStop > from and pStart < toSec then out.Push(p)
        end if
    end for
    return out
end function

' EPG map key for one channel record. The map is keyed by the channel's
' epgId, falling back to its own id - and LiveTvLineupEpg() builds it with
' those same two fields in that same order, so the two can never disagree.
function LiveTvGridEntryKey(ch as Object) as String
    if ch = invalid then return ""
    k = SafeStr(ch, "epgId", "")
    if k = "" then k = SafeStr(ch, "id", "")
    return k
end function

' Programme list for one channel, in the { title, start, stop } contract the
' block builder wants.
'
' WHY TWO SOURCES. This used to read from ONE place: the epg map that
' LiveTvLineupEpg() builds on the task thread and hands over as an
' assocarray field. That is a cross-thread copy, and when the copy does not
' carry the nested per-channel programme arrays the lookup misses for EVERY
' row - SILENTLY, because LiveTvGridBuildRow then falls back to a single
' always-on block titled with the CHANNEL NAME. That is exactly the "the
' grid just repeats the same channel names instead of the lineup" report,
' and it agrees with the device log: blocks=10 for 10 rows on a 90-channel
' guide, where a working lookup yields dozens of programme blocks.
' The channel record carries the SAME programme list in the SAME shape
' (LiveTvParseChannels attaches it while parsing the channel index), and it
' travels in the same channels field the rest of this screen already renders
' from - so it is the fallback source here. The epg map is still tried
' first: it is the only source once the XMLTV guide has upgraded an entry
' with <desc> text, and the XMLTV window is the authoritative one.
function LiveTvGridProgramList(st as Object, ch as Object) as Object
    if ch = invalid then return []
    if st <> invalid and type(st.epg) = "roAssociativeArray" then
        key = LiveTvGridEntryKey(ch)
        if key <> "" then
            e = st.epg[key]
            if type(e) = "roAssociativeArray" then
                list = LiveTvGridNormalizePrograms(SafeGet(e, "programs", invalid))
                if type(list) = "roArray" and list.count() > 0 then return list
            end if
        end if
        ' Title lookup, for a feed whose records and map disagree on the id.
        nk = LiveTvStvgNormKey(LiveTvGridChanName(ch))
        if nk <> "" then
            e = st.epg[nk]
            if type(e) = "roAssociativeArray" then
                list = LiveTvGridNormalizePrograms(SafeGet(e, "programs", invalid))
                if type(list) = "roArray" and list.count() > 0 then return list
            end if
        end if
    end if
    return LiveTvGridNormalizePrograms(SafeGet(ch, "programs", invalid))
end function

' Accept either programme shape and return { title, start, stop } records.
' An already-converted list passes straight through - the XMLTV path owns its
' own stop values - and the raw [[epoch, "Title"]] pairs the channel index
' itself ships are converted here, each block ending where the next one
' starts: the same rule LiveTvLineupPrograms applies on the task thread. Both
' are accepted because dropping the raw form silently puts the entire grid
' back on the channel-name fallback, which is the bug this whole path exists
' to kill.
function LiveTvGridNormalizePrograms(raw) as Object
    if raw = invalid or type(raw) <> "roArray" then return []
    out = []
    for each p in raw
        if type(p) = "roAssociativeArray" then
            s = LiveTvToInt(SafeGet(p, "start", 0))
            if s > 0 then
                prog = { title: LiveTvProgTitle(p), start: s }
                ' Bracketed, never a literal "stop:" key: stop is a reserved word.
                prog["stop"] = LiveTvToInt(SafeGet(p, "stop", 0))
                out.Push(prog)
            end if
        else if type(p) = "roArray" and p.count() >= 2 then
            s = LiveTvToInt(p[0])
            if s > 0 then
                ttl = ""
                if type(p[1]) = "String" or type(p[1]) = "roString" then ttl = p[1].Trim()
                if ttl <> "" then
                    prog = { title: ttl, start: s }
                    prog["stop"] = s
                    out.Push(prog)
                end if
            end if
        end if
    end for
    if out.count() = 0 then return out
    out = LiveTvSortProgramsByStart(out)
    n = out.count()
    for i = 0 to n - 1
        endSec = 0
        if i < n - 1 then endSec = LiveTvToInt(SafeGet(out[i + 1], "start", 0))
        curStart = LiveTvToInt(SafeGet(out[i], "start", 0))
        if endSec <= curStart then endSec = curStart + 1800
        out[i]["stop"] = endSec
    end for
    return out
end function

' 'y' is deliberately NOT a parameter: since rows became virtualised, the
' vertical offset is resolved in LiveTvGridTimePositions from the block's own
' chIdx (r.y + 6), so threading a y in here was dead weight.
sub LiveTvGridAddBlock(st as Object, chIdx as Integer, pStart as Integer, pStop as Integer, title as String, kind as String, isLive as Boolean)
    lay = st.layout
    g = CreateObject("roSGNode", "Group")
    ' Start hidden: a block is only revealed by LiveTvGridTimePositions once it
    ' has a real translation. An unpositioned block would otherwise draw at
    ' [0,0] on top of the first row.
    g.visible = false
    st.rowsRoot.appendChild(g)
    ' Track the group on the row that is being built so a re-render can
    ' remove it again (all row nodes are siblings under rowsRoot, not
    ' children of the row background).
    if st.buildNodes <> invalid then
        st.buildNodes.Push(g)
    end if
    rect = CreateObject("roSGNode", "Rectangle")
    ' Cable-guide colouring: what is on air now is the loudest thing in the
    ' row, what already finished recedes, what is still to come sits in the
    ' middle. A premium always-on row gets its own indigo.
    if kind = "ondemand" then
        rect.color = "0x312E81FF"
    else if isLive then
        rect.color = "0x9F1239FF"
    else if pStop <= st.now then
        rect.color = "0x111827FF"
    else
        rect.color = "0x1E293BFF"
    end if
    rect.height = lay.rowH - 20
    g.appendChild(rect)
    ' A 3px accent on the leading edge of the on-air block, the way a cable
    ' guide marks "you are here".
    if isLive or kind = "ondemand" then
        accent = CreateObject("roSGNode", "Rectangle")
        accent.color = "0xF8FAFCFF"
        accent.width = 3
        accent.height = lay.rowH - 20
        accent.translation = "[0,0]"
        g.appendChild(accent)
    end if
    lb = CreateObject("roSGNode", "Label")
    if pStop <= st.now and kind <> "ondemand" then
        lb.color = "0x8A93A5FF"
    else
        lb.color = "0xFFFFFFFF"
    end if
    lb.font = "font:SmallSystemFont"
    ' Block is 56px tall (rowH-20) and holds TWO lines: title on top, time
    ' range underneath. Centring the title across the full block height
    ' pushed its baseline down into the range label, so the two overprinted
    ' each other. Fixed split: title 3..29, range 34..54. These initial
    ' values match what LiveTvGridTimePositions writes, so the first paint
    ' does not jump.
    lb.height = 26
    lb.vertAlign = "center"
    lb.translation = "[8,3]"
    lb.maxLines = 1
    g.appendChild(lb)
    ' Time range under the title, cable-style. Only meaningful once the block
    ' is wide enough to hold it, and a Label cannot be measured, so the width
    ' threshold is derived from the character count: ~6.2px per char in the
    ' small system font.
    rng = CreateObject("roSGNode", "Label")
    rng.color = "0xB6C0D0FF"
    rng.font = "font:SmallSystemFont"
    rng.height = 20
    rng.translation = "[8,34]"
    rng.text = LiveTvClockOfDay(pStart) + " - " + LiveTvClockOfDay(pStop)
    g.appendChild(rng)
    entry = { rect: rect, label: lb, range: rng, grp: g, start: pStart, stop: pStop, kind: kind, isLive: isLive, chIdx: chIdx }
    entry["title"] = title
    ' -1 forces the first geometry pass to write; see LiveTvGridTimePositions.
    entry["lastX"] = -1
    entry["lastW"] = -1
    st.blocks.Push(entry)
end sub

' Horizontal paging without a rebuild: rewrite x/width on existing blocks.
' One pass - each block resolves its own row for the y offset.
sub LiveTvGridTimePositions(st as Object)
    if st = invalid then return
    lay = st.layout
    if lay = invalid then return
    if st.blocks = invalid then return
    right = lay.timeX + lay.timeW
        for each b in st.blocks
            r = LiveTvGridRowOf(st, b.chIdx)
            if r <> invalid and b.grp <> invalid and b.rect <> invalid and b.label <> invalid then
                x = lay.timeX + Int((b.start - st.winStart) / 60.0 * lay.pxPerMin)
                ' Blocks that begin past the right edge have to be HIDDEN, not
                ' merely skipped. They are already children of rowsRoot, so
                ' leaving them untouched leaves every one of them at its default
                ' translation [0,0] and visible - which piles all the off-window
                ' programs into the top-left corner of the grid. (Written as a
                ' nested if rather than "continue for", which is not available
                ' on every firmware and was never compiled on hardware.)
                if x >= right then
                    b.grp.visible = false
                else
                    b.grp.visible = true
                    w = Int((b.stop - b.start) / 60.0 * lay.pxPerMin)
                    ' Clamp to the window so a long movie reads as "continues".
                    if x < lay.timeX then
                        w = w + (x - lay.timeX)
                        x = lay.timeX
                    end if
                    if x + w > right then w = right - x
                    if w < 24 then w = 24
                    ' Only touch a block whose geometry actually moved. Every
                    ' property write invalidates layout, and a time scroll
                    ' rewrote all ~100 blocks even when the window shifted by
                    ' one pixel, which is what made LEFT/RIGHT feel like a
                    ' stall. b.lastX / b.lastW start at -1 so the first pass
                    ' always writes.
                    if b.lastX <> x or b.lastW <> w then
                        b.grp.translation = "[" + x.ToStr() + "," + (r.y + 6).ToStr() + "]"
                        b.rect.width = w
                        b.label.width = w - 14
                        if b.label.width < 10 then b.label.width = 10
                        ' Title sits on the top line, the time range under it,
                        ' and the range is dropped entirely on a narrow block so
                        ' it cannot collide with the title.
                        b.label.translation = "[8,3]"
                        b.label.height = 26
                        if b.range <> invalid then
                            if w >= 150 then
                                b.range.visible = true
                                b.range.width = w - 16
                            else
                                b.range.visible = false
                            end if
                        end if
                        b.lastX = x
                        b.lastW = w
                    end if
                    ' The title keeps the 26px band set above and the range sits
                    ' under it at 34. This used to re-assert
                    ' b.label.height = lay.rowH - 20 (the full 56px block) right
                    ' here, which undid the two-band fix in LiveTvGridAddBlock:
                    ' with vertAlign=center the title re-centred over the WHOLE
                    ' block, dropping its baseline onto the range label and
                    ' overprinting the time. Height is written once, at build.
                    b.label.text = b.title
                end if
            end if
        end for
    LiveTvGridNowLine(st)
end sub

function LiveTvGridRowOf(st as Object, chIdx as Integer) as Object
    for each r in st.rows
        if r.chIdx = chIdx then return r
    end for
    return invalid
end function

sub LiveTvGridNowLine(st as Object)
    if st = invalid then return
    lay = st.layout
    if lay = invalid then return
    ' Playhead nodes are created by LiveTvGridBuild. LiveTvGridClear leaves
    ' them as detached (but valid) nodes, and a tick can fire before the
    ' first build, so guard before touching .visible.
    if st.nowLine = invalid or st.nowPill = invalid then return
    x = lay.timeX + Int((st.now - st.winStart) / 60.0 * lay.pxPerMin)
    inside = (x >= lay.timeX) and (x <= lay.timeX + lay.timeW)
    st.nowLine.visible = inside
    st.nowPill.visible = inside
    if st.nowPillBg <> invalid then st.nowPillBg.visible = inside
    if inside then
        st.nowLine.translation = "[" + x.ToStr() + "," + (lay.y0 + lay.rulerH).ToStr() + "]"
        ' Pill sits ON the ruler's bottom edge, not over the first row's text.
        py = lay.y0 + lay.rulerH - 14
        if st.nowPillBg <> invalid then
            st.nowPillBg.translation = "[" + (x - 35).ToStr() + "," + py.ToStr() + "]"
        end if
        st.nowPill.translation = "[" + (x - 35).ToStr() + "," + py.ToStr() + "]"
    end if
end sub

' Keep the focused row inside the virtualized window.
function LiveTvGridClampFirst(st as Object, focusIdx as Integer) as Integer
    lay = st.layout
    total = 0
    if st.channels <> invalid then total = st.channels.count()
    maxFirst = total - lay.rows
    if maxFirst < 0 then maxFirst = 0
    f = st.first
    if f < 0 then f = 0
    if f > maxFirst then f = maxFirst
    if focusIdx < f then f = focusIdx
    if focusIdx >= f + lay.rows then f = focusIdx - lay.rows + 1
    if f < 0 then f = 0
    if f > maxFirst then f = maxFirst
    return f
end function

sub LiveTvGridFocusStep(st as Object, delta as Integer)
    total = 0
    if st.channels <> invalid then total = st.channels.count()
    if total = 0 then return
    idx = st.focus + delta
    if idx < 0 then idx = 0
    if idx >= total then idx = total - 1
    if idx = st.focus then return
    st.focus = idx
    ' FREEZE FIX. This used to call LiveTvGridRenderRows unconditionally, so a
    ' single UP/DOWN tore down and rebuilt every node for 10 rows - background,
    ' gutter labels, and one Group+Rectangle+Label per program block. Holding
    ' the key could rebuild hundreds of nodes per second, which is what made
    ' the grid feel locked up. A rebuild is only needed when the focused row
    ' has actually left the rendered window; otherwise repaint the highlight,
    ' which touches 3 nodes per visible row.
    if st.layout = invalid or st.rows = invalid then
        LiveTvGridRenderRows(st)
        return
    end if
    if idx < st.first or idx >= st.first + st.layout.rows then
        st.first = LiveTvGridClampFirst(st, idx)
        LiveTvGridRenderRows(st)
    else
        LiveTvGridPaintFocus(st)
    end if
end sub

sub LiveTvGridScrollTime(st as Object, deltaMin as Integer)
    st.winStart = st.winStart + deltaMin * 60
    ' Keep the window sane around now: at most 4h back, 2h ahead.
    low = st.now - Int(240 * 60)
    high = st.now + Int(120 * 60)
    if st.winStart < low then st.winStart = low
    if st.winStart > high then st.winStart = high
    ' Snap to a real :00/:30 boundary. Without this, paging by an odd number
    ' of minutes slides the ruler labels and the gridlines off the hour marks,
    ' and repeated paging accumulates the drift until the timetable lies.
    st.winStart = LiveTvGridSnapHalfHour(st.winStart)
    LiveTvGridRuler(st)
    LiveTvGridTimePositions(st)
end sub

sub LiveTvGridJumpNow(st as Object)
    st.now = LiveTvNowSec()
    st.winStart = LiveTvGridSnapHalfHour(st.now - Int(30 * 60))
    LiveTvGridRuler(st)
    ' Window moved far enough that a rebuild is cheaper than re-clamping.
    LiveTvGridRenderRows(st)
end sub

' Clock tick: advance the playhead and follow "now" if it rolled off.
sub LiveTvGridTick(st as Object)
    if st = invalid then return
    n = LiveTvNowSec()
    st.now = n
    lay = st.layout
    if lay = invalid then return
    if st.winStart + Int(lay.spanMin * 60) < n then
        st.winStart = LiveTvGridSnapHalfHour(n - Int(30 * 60))
        LiveTvGridRuler(st)
        LiveTvGridRenderRows(st)
        return
    end if
    ' Programme boundaries are not tied to the 30s tick: rebuild the visible
    ' rows every couple of minutes so the live block and the block after it
    ' stop showing the previous programme's title/colour.
    last = st.lastRowNow
    if last = invalid or (n - last) >= 120 then
        LiveTvGridRenderRows(st)
        return
    end if
    LiveTvGridNowLine(st)
end sub

' Focus highlight: repaint row backgrounds without a full rebuild.
sub LiveTvGridPaintFocus(st as Object)
    for each r in st.rows
        isF = (r.chIdx = st.focus)
        if r.bg <> invalid then
            if isF then
                r.bg.color = "0x1E293BFF"
            else if (r.chIdx mod 2) = 0 then
                r.bg.color = "0x0D1320FF"
            else
                r.bg.color = "0x0A0F19FF"
            end if
        end if
        ' The red bar in the gutter is the only thing that says which channel
        ' the arrow keys are on - the row tint alone is too subtle on a TV.
        if r.focusBar <> invalid then
            r.focusBar.visible = isF
        end if
        if r.numBg <> invalid then
            if isF then
                r.numBg.color = "0xD42028FF"
            else
                r.numBg.color = "0x1F2937FF"
            end if
        end if
        if r.num <> invalid then
            if isF then
                r.num.color = "0xFFFFFFFF"
            else
                r.num.color = "0x9CA3AFFF"
            end if
        end if
        if r.name <> invalid then
            if isF then
                r.name.color = "0xFFFFFFFF"
            else
                r.name.color = "0xD1D5DBFF"
            end if
        end if
    end for
end sub

' Tear the grid down (scene keeps the node; we just clear its children).
sub LiveTvGridClear(st as Object, root as Object)
    if root = invalid then return
    kids = root.getChildren(-1, 0)
    for each k in kids
        root.removeChild(k)
    end for
    st.rows = []
    st.blocks = []
    st.withProgs = 0
    st.buildNodes = invalid
    st.lastRowNow = invalid
    st.rulerLabels = []
    st.rulerTicks = []
    st.colLines = []
    st.clock = invalid
end sub

function LiveTvGridFocusChannel(st as Object) as Object
    if st = invalid or st.channels = invalid then return invalid
    i = st.focus
    if i < 0 then i = 0
    if i >= st.channels.count() then return invalid
    return st.channels[i]
end function

' "2:30 PM" style label for the ruler.
' FromSeconds() is UTC, so ToLocalTime() is REQUIRED or the ruler disagrees
' with the NOW line, the guide rows and the info card (which all go through
' LiveTvEpochClock, also local). GetHours/GetMinutes match that path and are
' the only shape every roDateTime build here accepts (AsHoursAndMinutes is
' missing from the verification emulator's roDateTime interface).
function LiveTvClockOfDay(epoch as Integer) as String
    if epoch = invalid then return ""
    if epoch <= 0 then return ""
    dt = CreateObject("roDateTime")
    dt.FromSeconds(epoch)
    dt.ToLocalTime()
    h = dt.GetHours()
    mi = dt.GetMinutes()
    ap = "AM"
    hh = h
    if h >= 12 then
        ap = "PM"
        hh = h - 12
    end if
    if hh = 0 then hh = 12
    if mi < 10 then return hh.ToStr() + ":0" + mi.ToStr() + " " + ap
    return hh.ToStr() + ":" + mi.ToStr() + " " + ap
end function
