sub init()
    m.keyLabel = m.top.findNode("keyLabel")
    m.keyRect = m.top.findNode("keyRect")
    m.keyEdge = m.top.findNode("keyEdge")
    m.keyGlow = m.top.findNode("keyGlow")
    m.keyFocusEdge = m.top.findNode("keyFocusEdge")
    m.top.observeField("itemContent", "OnKeyContent")
    m.top.observeField("content", "OnKeyContent")
    m.top.observeField("focusPercent", "OnKeyFocus")
    OnKeyContent(invalid)
    OnKeyFocus(invalid)
end sub

sub ApplyKeySize()
    w = m.top.width
    h = m.top.height
    if type(w) <> "roFloat" and type(w) <> "Float" and type(w) <> "roInt" and type(w) <> "roInteger" and type(w) <> "Integer" then
        w = 120
    end if
    if type(h) <> "roFloat" and type(h) <> "Float" and type(h) <> "roInt" and type(h) <> "roInteger" and type(h) <> "Integer" then
        h = 100
    end if
    if w <= 0 then
        w = 120
    end if
    if h <= 0 then
        h = 100
    end if
    m.keyRect.width = w
    m.keyRect.height = h
    m.keyLabel.width = w
    m.keyLabel.height = h
    if m.keyEdge <> invalid then
        m.keyEdge.width = w
    end if
    if m.keyFocusEdge <> invalid then
        m.keyFocusEdge.width = w
    end if
    if m.keyGlow <> invalid then
        m.keyGlow.width = w + 8
        m.keyGlow.height = h + 8
    end if
end sub

sub OnKeyContent(msg as Object)
    c = m.top.itemContent
    if c = invalid then
        c = m.top.content
    end if
    if c = invalid then
        ' Was a leftover debug print: it fired once per keypad key cell on
        ' every render and buried the real diagnostics under ~60 identical
        ' log lines per search.
        return
    end if
    ApplyKeySize()
    label = ""
    if c <> invalid then
        label = c.title
        if label = invalid then
            label = ""
        end if
    end if
    if label = "" then
        m.keyRect.visible = false
        m.keyLabel.visible = false
        if m.keyEdge <> invalid then m.keyEdge.visible = false
        if m.keyGlow <> invalid then m.keyGlow.visible = false
        if m.keyFocusEdge <> invalid then m.keyFocusEdge.visible = false
        return
    end if
    m.keyRect.visible = true
    m.keyLabel.visible = true
    if m.keyEdge <> invalid then m.keyEdge.visible = true
    if label = "SPACE" then
        m.keyLabel.text = "space"
    else
        m.keyLabel.text = label
    end if
    KeyTintLabel()
end sub

' Unfocused keycap text: dim gray, action keys (DONE / CANCEL) in soft red
' so they read as actions at 10-foot distance. Focused state is handled in
' OnKeyFocus (red keycap + white text).
sub KeyTintLabel()
    if m.keyLabel = invalid then return
    fp = m.top.focusPercent
    if fp <> invalid then
        if fp >= 0.5 then return
    end if
    c = m.top.itemContent
    if c = invalid then c = m.top.content
    label = ""
    if c <> invalid then
        if c.title <> invalid then label = c.title
    end if
    if label = "DONE" or label = "CANCEL" then
        m.keyLabel.color = "0xF87171FF"
    else
        m.keyLabel.color = "0xC9CED6FF"
    end if
end sub

sub OnKeyFocus(msg as Object)
    if m.keyRect = invalid or m.keyRect.visible = false then
        return
    end if
    fp = m.top.focusPercent
    if fp = invalid then
        fp = 0
    end if
    if fp >= 0.5 then
        m.keyRect.color = "0xD42028FF"
        if m.keyLabel <> invalid then m.keyLabel.color = "0xFFFFFFFF"
        if m.keyGlow <> invalid then m.keyGlow.visible = true
        if m.keyFocusEdge <> invalid then m.keyFocusEdge.visible = true
        if m.keyEdge <> invalid then m.keyEdge.visible = false
    else
        m.keyRect.color = "0x232838FF"
        if m.keyGlow <> invalid then m.keyGlow.visible = false
        if m.keyFocusEdge <> invalid then m.keyFocusEdge.visible = false
        if m.keyEdge <> invalid then m.keyEdge.visible = true
        KeyTintLabel()
    end if
end sub
