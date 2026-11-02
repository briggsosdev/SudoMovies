' GenrePageItem: text-only chip used by the genre browser's tab strip and page
' bar. Both are single-row RowLists, so this is a RowList item component.
'
' Rules this file follows (each one was a bug in the previous version):
'   * Item components are NOT focused nodes, so didGainFocus/didLoseFocus are
'     never called on them. Focus arrives through the itemHasFocus /
'     focusPercent / rowListHasFocus fields, which are observed below.
'   * Node color fields are assigned as QUOTED strings ("0xAARRGGBB").
'   * Content is delivered by setting `itemContent`; nothing calls a handler
'     for you, so init() observes it and also reads it once directly.
'   * The cell watches the bound ContentNode's title/selected/enabled fields,
'     so the browser can update a chip in place (no content rebuild, which
'     would reset the list's focus position).
sub init()
    m.plate = m.top.findNode("plate")
    m.label = m.top.findNode("label")
    m.bound = invalid
    m.text = ""
    m.enabled = true
    m.selected = false
    m.top.observeField("itemContent", "OnItemContentChanged")
    m.top.observeField("content", "OnItemContentChanged")
    m.top.observeField("itemHasFocus", "OnFocusChanged")
    m.top.observeField("focusPercent", "OnFocusChanged")
    m.top.observeField("rowListHasFocus", "OnFocusChanged")
    m.top.observeField("width", "OnFocusChanged")
    m.top.observeField("height", "OnFocusChanged")
    OnItemContentChanged(invalid)
end sub

sub OnItemContentChanged(msg as Object)
    c = m.top.itemContent
    if c = invalid then c = m.top.content
    if c = invalid then return
    ' Stop watching the previously bound node (cells are recycled).
    if m.bound <> invalid then
        UnwatchNode(m.bound)
    end if
    m.bound = c
    WatchNode(c)
    ReadBound()
end sub

sub WatchNode(c as Object)
    flds = ["title", "selected", "enabled"]
    for each f in flds
        if c.hasField(f) then c.observeField(f, "OnBoundChanged")
    end for
end sub

sub UnwatchNode(c as Object)
    flds = ["title", "selected", "enabled"]
    for each f in flds
        if c.hasField(f) then c.unobserveField(f)
    end for
end sub

sub OnBoundChanged()
    ReadBound()
end sub

sub ReadBound()
    c = m.bound
    if c = invalid then return
    m.text = ""
    tv = c.getField("title")
    if tv <> invalid then
        if type(tv) = "roString" or type(tv) = "String" then
            m.text = tv
        else
            m.text = tv.ToStr()
        end if
    end if
    m.enabled = true
    if c.hasField("enabled") then
        ev = c.getField("enabled")
        if ev <> invalid then m.enabled = (ev = true)
    end if
    m.selected = false
    if c.hasField("selected") then
        sv = c.getField("selected")
        if sv <> invalid then m.selected = (sv = true)
    end if
    ApplyLook()
end sub

sub OnFocusChanged()
    ApplyLook()
end sub

function IsLive() as Boolean
    if m.top.itemHasFocus = true then return true
    if m.top.rowListHasFocus = true then
        fp = m.top.focusPercent
        if fp <> invalid and fp >= 0.5 then return true
    end if
    return false
end function

sub ApplyLook()
    w = m.top.width
    h = m.top.height
    if w = invalid or w <= 0 then w = 180
    if h = invalid or h <= 0 then h = 44
    focused = IsLive()

    if m.plate <> invalid then
        m.plate.width = w
        m.plate.height = h
        if focused and m.enabled then
            m.plate.color = "0xD42028FF"
        else if focused then
            m.plate.color = "0x2A3350FF"
        else if not m.enabled then
            m.plate.color = "0x141A28FF"
        else if m.selected then
            m.plate.color = "0x8B1A1FFF"
        else
            m.plate.color = "0x1B2233FF"
        end if
    end if
    if m.label <> invalid then
        m.label.width = w - 12
        m.label.height = h
        m.label.text = m.text
        if not m.enabled then
            m.label.color = "0x7C869BFF"
        else if focused or m.selected then
            m.label.color = "0xFFFFFFFF"
        else
            m.label.color = "0xB0B8C8FF"
        end if
    end if
end sub
