sub init()
    m.liveTvItemLogo = m.top.findNode("logo")
    m.liveTvItemNum = m.top.findNode("numLabel")
    m.liveTvItemTitle = m.top.findNode("titleLabel")
    m.liveTvItemSub = m.top.findNode("subLabel")
    m.liveTvItemNowDot = m.top.findNode("nowDot")
    m.liveTvItemFocusShadow = m.top.findNode("focusShadow")
    m.liveTvItemFocusRect = m.top.findNode("focusRect")
    m.liveTvItemEdge = m.top.findNode("itemEdge")
    m.top.observeField("itemContent", "LiveTvItemOnContent")
    m.top.observeField("content", "LiveTvItemOnContent")
    m.top.observeField("focusPercent", "LiveTvItemOnFocus")
    LiveTvItemOnFocus(invalid)
end sub

sub LiveTvItemOnFocus(msg as Object)
    if m.liveTvItemFocusRect = invalid then return
    fp = m.top.focusPercent
    if fp = invalid then fp = 0
    focused = (fp >= 0.5)
    m.liveTvItemFocusRect.visible = focused
    if m.liveTvItemEdge <> invalid then
        m.liveTvItemEdge.visible = focused
    end if
    if m.liveTvItemFocusShadow <> invalid then
        m.liveTvItemFocusShadow.visible = focused
    end if
    if m.liveTvItemTitle <> invalid then
        if focused then
            m.liveTvItemTitle.color = "0xFFFFFFFF"
        else
            m.liveTvItemTitle.color = "0xF5F5F5FF"
        end if
    end if
    if m.liveTvItemSub <> invalid then
        if focused then
            m.liveTvItemSub.color = "0xFFFFFFFF"
        else
            m.liveTvItemSub.color = "0xE5E7EBFF"
        end if
    end if
end sub

sub LiveTvItemOnContent(msg as Object)
    c = m.top.itemContent
    if c = invalid then c = m.top.content
    if c = invalid then return
    uri = ""
    if c.HDPosterUrl <> invalid then uri = c.HDPosterUrl
    if uri = "" then uri = "pkg:/images/poster_placeholder.png"
    if m.liveTvItemLogo <> invalid then m.liveTvItemLogo.uri = uri
    num = ""
    if c.shortDescriptionLine1 <> invalid then num = c.shortDescriptionLine1.ToStr()
    if m.liveTvItemNum <> invalid then
        if num <> "" then
            ' Free FAST tiles pass a channel number ("1004"); premium tiles
            ' pass a category tag ("SPORTS"). Only numbers get the CH prefix.
            if LiveTvItemIsNumeric(num) then
                m.liveTvItemNum.text = "CH " + num
            else
                m.liveTvItemNum.text = num
            end if
        else
            m.liveTvItemNum.text = ""
        end if
    end if
    title = ""
    if c.title <> invalid then title = c.title.ToStr()
    if m.liveTvItemTitle <> invalid then m.liveTvItemTitle.text = title
    sub2 = ""
    if c.shortDescriptionLine2 <> invalid then sub2 = c.shortDescriptionLine2.ToStr()
    if m.liveTvItemSub <> invalid then
        if sub2 <> "" then
            m.liveTvItemSub.text = "NOW  " + sub2
        else
            m.liveTvItemSub.text = ""
        end if
    end if
    ' Premium channels have no guide data: hide the NOW dot instead of
    ' showing a lone red dot under the title.
    if m.liveTvItemNowDot <> invalid then
        m.liveTvItemNowDot.visible = (sub2 <> "")
    end if
end sub

' True when s is a plain non-negative integer string ("" is not numeric).
function LiveTvItemIsNumeric(s as String) as Boolean
    if s = invalid or s = "" then
        return false
    end if
    for i = 1 to s.Len()
        code = Asc(Mid(s, i, 1))
        if code < 48 or code > 57 then
            return false
        end if
    end for
    return true
end function
