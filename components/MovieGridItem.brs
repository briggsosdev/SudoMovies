sub init()
    m.poster = m.top.findNode("poster")
    m.titleLabel = m.top.findNode("titleLabel")
    m.yearLabel = m.top.findNode("yearLabel")
    m.focusShadow = m.top.findNode("focusShadow")
    m.focusRect = m.top.findNode("focusRect")
    m.focusInner = m.top.findNode("focusInner")
    m.playScrim = m.top.findNode("playScrim")
    m.playBadge = m.top.findNode("playBadge")
    m.playHint = m.top.findNode("playHint")
    m.titleScrim = m.top.findNode("titleScrim")
    m.focusGlow = m.top.findNode("focusGlow")
    m.rankShadow = m.top.findNode("rankShadow")
    m.rankLabel = m.top.findNode("rankLabel")
    m.ratingBadge = m.top.findNode("ratingBadge")
    m.ratingLabel = m.top.findNode("ratingLabel")
    m.progressTrack = m.top.findNode("progressTrack")
    m.progressFill = m.top.findNode("progressFill")
    m.rankNum = 0
    m.progressPct = 0
    m.chipText = ""
    m.hasBadge = false
    m.badgeText = ""
    m.top.observeField("itemContent", "OnItemContentChanged")
    m.top.observeField("content", "OnItemContentChanged")
    m.top.observeField("focusPercent", "OnItemFocus")
    OnItemFocus(invalid)
end sub

sub OnItemFocus(msg as Object)
    if m.focusRect = invalid then
        return
    end if
    fp = m.top.focusPercent
    if fp = invalid then
        fp = 0
    end if
    focused = (fp >= 0.5)
    m.focusRect.visible = focused
    if m.focusInner <> invalid then
        m.focusInner.visible = focused
    end if
    if m.yearLabel <> invalid then
        if focused then
            m.yearLabel.color = "0xE5E7EBFF"
        else
            m.yearLabel.color = "0x9CA3AFFF"
        end if
    end if
    if m.focusShadow <> invalid then
        m.focusShadow.visible = focused
        if focused then
            m.focusShadow.color = "0x000000AA"
        else
            m.focusShadow.color = "0x00000033"
        end if
    end if
    if m.focusGlow <> invalid then
        m.focusGlow.visible = focused
    end if
    if m.ratingBadge <> invalid and m.chipText <> "" then
        m.ratingBadge.visible = true
        if focused then
            m.ratingBadge.color = "0xD42028FF"
        else
            m.ratingBadge.color = "0x000000B3"
        end if
    end if
    if m.ratingLabel <> invalid and m.chipText <> "" then
        m.ratingLabel.visible = true
        if focused then
            m.ratingLabel.color = "0xFFFFFFFF"
        else
            m.ratingLabel.color = "0xFFD75EFF"
        end if
    end if
    if m.rankLabel <> invalid and m.rankNum > 0 then
        m.rankLabel.visible = true
        if focused then
            m.rankLabel.color = "0xFFD75EFF"
        else
            m.rankLabel.color = "0xFFFFFFFF"
        end if
    end if
    if m.rankShadow <> invalid and m.rankNum > 0 then
        m.rankShadow.visible = true
    end if
    ' Action badge: real titles show the play scrim + PLAY CTA; special rows
    ' (SEARCH/SETTINGS/...) override the text via a "badge" content field, and
    ' non-playable empty tiles set badge="" to hide the scrim entirely.
    showPlay = false
    if focused then
        if not m.hasBadge then
            showPlay = true
        else if m.badgeText <> "" then
            showPlay = true
        end if
    end if
    if m.playScrim <> invalid then
        m.playScrim.visible = showPlay
        if showPlay then
            m.playScrim.color = "0x00000088"
        else
            m.playScrim.color = "0x00000066"
        end if
    end if
    if m.playBadge <> invalid then
        m.playBadge.visible = showPlay
    end if
    if m.playHint <> invalid then
        m.playHint.visible = showPlay
    end if
    if m.titleLabel <> invalid then
        if focused then
            m.titleLabel.color = "0xFFFFFFFF"
        else
            m.titleLabel.color = "0xF5F5F5FF"
        end if
    end if
end sub

sub OnItemContentChanged(msg as Object)
    c = m.top.itemContent
    if c = invalid then
        c = m.top.content
    end if
    if c = invalid then
        ? "TILE content=invalid"
        return
    end if
    t = ""
    if c.title <> invalid then t = c.title.ToStr()
    ? "TILE content title=" + t

    ' Read the optional "badge" content field (addField'd by HomeScene for
    ' special/empty rows). hasField before any custom field read, else
    ' SceneGraph throws a runtime error. Reset both flags every bind so
    ' recycled row tiles never inherit the previous item's badge.
    m.hasBadge = false
    m.badgeText = ""
    m.rankNum = 0
    m.progressPct = 0
    m.chipText = ""
    if c.hasField("badge") then
        m.hasBadge = true
        bt = c.getField("badge")
        if bt <> invalid then
            if type(bt) = "roString" or type(bt) = "String" then
                m.badgeText = bt
            else
                m.badgeText = bt.ToStr()
            end if
        end if
    end if
    if c.hasField("rank") then
        rv = c.getField("rank")
        if rv <> invalid then
            m.rankNum = Int(rv)
        end if
    end if
    if c.hasField("progress") then
        pv = c.getField("progress")
        if pv <> invalid then
            m.progressPct = Int(pv)
            if m.progressPct < 0 then m.progressPct = 0
            if m.progressPct > 100 then m.progressPct = 100
        end if
    end if
    if c.hasField("chip") then
        cv = c.getField("chip")
        if cv <> invalid then
            if type(cv) = "roString" or type(cv) = "String" then
                m.chipText = cv
            else
                m.chipText = cv.ToStr()
            end if
        end if
    end if
    if m.playHint <> invalid then
        if m.hasBadge and m.badgeText <> "" then
            m.playHint.text = m.badgeText
        else
            m.playHint.text = "PLAY"
        end if
    end if

    w = m.top.width
    h = m.top.height
    if type(w) <> "Integer" and type(w) <> "roInt" and type(w) <> "Float" and type(w) <> "roFloat" then
        w = 200
    end if
    if type(h) <> "Integer" and type(h) <> "roInt" and type(h) <> "Float" and type(h) <> "roFloat" then
        h = 350
    end if
    if w <= 0 then
        w = 200
    end if
    if h <= 0 then
        h = 350
    end if

    posterH = h - 56
    posterW = w
    if m.focusGlow <> invalid then
        m.focusGlow.width = posterW + 24
        m.focusGlow.height = posterH + 24
        m.focusGlow.translation = "[-12,-12]"
    end if
    m.focusShadow.width = posterW + 16
    m.focusShadow.height = posterH + 16
    m.focusShadow.translation = "[-8,-8]"
    m.focusRect.width = posterW + 8
    m.focusRect.height = posterH + 8
    m.focusRect.translation = "[-4,-4]"
    if m.focusInner <> invalid then
        m.focusInner.width = posterW + 4
        m.focusInner.height = posterH + 4
        m.focusInner.translation = "[-2,-2]"
    end if
    m.poster.width = posterW
    m.poster.height = posterH
    ' Slim rows (badge tiles: SEARCH/SETTINGS/RELOAD/PROFILES/LIVE TV) are
    ' full-bleed 448x656 designs: scaleToFit letterboxed them to ~31% fill
    ' (design review). Full poster rows keep scaleToFit (no art cropping).
    if posterH < 200 then
        m.poster.loadDisplayMode = "scaleToFill"
    else
        m.poster.loadDisplayMode = "scaleToFit"
    end if
    m.poster.uri = c.HDPosterUrl
    if m.poster.uri = "" or m.poster.uri = invalid then
        m.poster.uri = "pkg:/images/poster_placeholder.png"
    end if

    if m.playScrim <> invalid then
        m.playScrim.width = posterW
        m.playScrim.height = posterH
    end if
    if m.titleScrim <> invalid then
        m.titleScrim.width = posterW
        ' 56 = the real text zone (title+year strip); 64 hung 8px past the
        ' tile bottom into the row gap (design review).
        m.titleScrim.height = 56
        m.titleScrim.translation = "[0," + posterH.ToStr() + "]"
        m.titleScrim.visible = true
    end if
    if m.playBadge <> invalid then
        ' 52 = badge bottom ends posterH-14, clearing the 10px resume bar
        ' at posterH-10 by 4px (design review; was -42 -> 6px overlap).
        m.playBadge.translation = "[12," + (posterH - 52).ToStr() + "]"
    end if
    if m.playHint <> invalid then
        m.playHint.translation = "[18," + (posterH - 52).ToStr() + "]"
        m.playHint.width = (posterW - 28)
    end if
    if m.rankShadow <> invalid then
        m.rankShadow.translation = "[6," + (posterH - 132).ToStr() + "]"
        if m.rankNum > 0 then
            m.rankShadow.text = m.rankNum.ToStr()
            m.rankShadow.visible = true
        else
            m.rankShadow.visible = false
        end if
    end if
    if m.rankLabel <> invalid then
        m.rankLabel.translation = "[2," + (posterH - 136).ToStr() + "]"
        if m.rankNum > 0 then
            m.rankLabel.text = m.rankNum.ToStr()
            m.rankLabel.visible = true
        else
            m.rankLabel.visible = false
        end if
    end if
    if m.ratingBadge <> invalid then
        m.ratingBadge.translation = "[" + (posterW - 80).ToStr() + ",8]"
        if m.chipText <> "" then
            m.ratingBadge.visible = true
        else
            m.ratingBadge.visible = false
        end if
    end if
    if m.ratingLabel <> invalid then
        m.ratingLabel.translation = "[" + (posterW - 80).ToStr() + ",8]"
        if m.chipText <> "" then
            m.ratingLabel.text = m.chipText
            m.ratingLabel.visible = true
        else
            m.ratingLabel.visible = false
        end if
    end if
    if m.progressTrack <> invalid then
        m.progressTrack.width = posterW
        m.progressTrack.translation = "[0," + (posterH - 10).ToStr() + "]"
        if m.progressPct > 0 then
            m.progressTrack.visible = true
        else
            m.progressTrack.visible = false
        end if
    end if
    if m.progressFill <> invalid then
        fillW = Int(posterW * m.progressPct / 100)
        m.progressFill.width = fillW
        m.progressFill.translation = "[0," + (posterH - 10).ToStr() + "]"
        if m.progressPct > 0 then
            m.progressFill.visible = true
        else
            m.progressFill.visible = false
        end if
    end if

    labelY = posterH + 4
    m.titleLabel.translation = "[4," + labelY.ToStr() + "]"
    m.titleLabel.width = (w - 4)
    m.titleLabel.height = 28
    if c.title <> invalid then
        m.titleLabel.text = c.title.ToStr()
    else
        m.titleLabel.text = ""
    end if

    m.yearLabel.translation = "[4," + (labelY + 30).ToStr() + "]"
    m.yearLabel.width = (w - 4)
    m.yearLabel.height = 20
    year = ""
    if c.shortDescriptionLine1 <> invalid then year = c.shortDescriptionLine1.ToStr()
    if year = "" then
        m.yearLabel.text = ""
    else
        m.yearLabel.text = year
    end if
    OnItemFocus(invalid)
end sub