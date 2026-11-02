' LiveTvChannelRow: one row of the Live TV channel guide.
'
' Pure view. The scene owns the data and writes it into the ContentNode the
' MarkupList hands over as itemContent:
'   title                  -> channel name
'   shortDescriptionLine1  -> channel number ("" hides the badge)
'   shortDescriptionLine2  -> the NOW line (already formatted by the scene)
'   description            -> the NEXT line (already formatted)
'
' Fields are read with hasField()/getField(): a ContentNode is an roSGNode,
' and SafeStr() (Tmdb.brs) deliberately bails out on non-assocarrays, so it
' would return "" for every row.

sub init()
    m.rowBg = m.top.findNode("rowBg")
    m.rowEdge = m.top.findNode("rowEdge")
    m.chPlate = m.top.findNode("chPlate")
    m.chLabel = m.top.findNode("chLabel")
    m.nameLabel = m.top.findNode("nameLabel")
    m.nowLabel = m.top.findNode("nowLabel")
    m.nextLabel = m.top.findNode("nextLabel")
    m.top.observeField("itemContent", "OnContent")
    m.top.observeField("content", "OnContent")
    m.top.observeField("focusPercent", "OnFocus")
    OnFocus(invalid)
end sub

sub OnContent(evt as Object)
    c = m.top.itemContent
    if c = invalid then c = m.top.content
    if c = invalid then return
    num = RowStr(c, "shortDescriptionLine1")
    if m.chLabel <> invalid then m.chLabel.text = num
    if m.chPlate <> invalid then m.chPlate.visible = (num <> "")
    if m.nameLabel <> invalid then m.nameLabel.text = RowStr(c, "title")
    if m.nowLabel <> invalid then m.nowLabel.text = RowStr(c, "shortDescriptionLine2")
    if m.nextLabel <> invalid then m.nextLabel.text = RowStr(c, "description")
end sub

sub OnFocus(evt as Object)
    fp = m.top.focusPercent
    if fp = invalid then fp = 0
    focused = (fp >= 0.5)
    if m.rowBg <> invalid then
        if focused then
            m.rowBg.color = "0x18233CFF"
        else
            m.rowBg.color = "0x0D1320FF"
        end if
    end if
    if m.rowEdge <> invalid then m.rowEdge.visible = focused
    if m.chPlate <> invalid then
        if focused then
            m.chPlate.color = "0xD42028FF"
        else
            m.chPlate.color = "0x1F2937FF"
        end if
    end if
    if m.nameLabel <> invalid then
        if focused then
            m.nameLabel.color = "0xFFFFFFFF"
        else
            m.nameLabel.color = "0xF0F2F5FF"
        end if
    end if
    if m.nowLabel <> invalid then
        if focused then
            m.nowLabel.color = "0xFFFFFFFF"
        else
            m.nowLabel.color = "0xD5DAE3FF"
        end if
    end if
    if m.nextLabel <> invalid then
        if focused then
            m.nextLabel.color = "0xAEB6C4FF"
        else
            m.nextLabel.color = "0x7F8899FF"
        end if
    end if
end sub

' Field read for a ContentNode. Missing/typeless fields degrade to "".
function RowStr(n as Object, field as String) as String
    if n = invalid then return ""
    if type(n) <> "roSGNode" then return ""
    if not n.hasField(field) then return ""
    v = n.getField(field)
    if v = invalid then return ""
    if type(v) = "roString" or type(v) = "String" then return v
    return v.ToStr()
end function
