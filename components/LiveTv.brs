' LiveTv.brs — pure data-layer helpers for the free USA FAST lineup.
'
' Source: Samsung TV Plus channel index + XMLTV guide proxied by i.mjh.nz.
'   VERIFIED 2026-09-19 (plain HTTPS GET from a PC, no device involved):
'     .channels.json (plain JSON index) -> HTTP 200, application/json,
'       1908716 bytes, shape { slug: "stvp-{id}", regions: { us: { channels:
'       { ID: { name, chno, logo, description, group, programs } } } } } with
'       582 US channels, every one carrying a real chno (1000, 1001, ...),
'       group and logo. LiveTvParseChannels() consumes exactly this shape.
'       The feed's own slug field ("stvp-{id}") is the sanction for the
'       stream URL shape built by LiveTvStreamUrl().
'     us.xml (plain XMLTV) -> HTTP 200, text/plain, 3002315 bytes, 582
'       <channel> blocks (every one with display-name + icon src) and 4984
'       <programme> blocks (channel/start/stop/title/desc, timestamps
'       "yyyyMMddHHmmss +0000", guide coverage 09:30Z today -> 03:00Z
'       tomorrow). THE single source for the guide, and the lineup fallback
'       via LiveTvParseChannelsFromXmltv() if the JSON index ever dies again.
'     .channels.json.gz -> 302 -> raw.githubusercontent.com -> HTTP 200,
'       application/octet-stream, 542344 bytes, gzip magic 1f 8b, and NO
'       Content-Encoding header. Unusable on-device (no gunzip primitive),
'       so the task NEVER requests any .gz URL.
'   Stream URL shape: https://jmp2.uk/stvp-{CHANNEL_ID} (302 -> rotating CDN
'     -> multivariant HLS master). Verified 2026-09-19 with two real IDs:
'       stvp-USBA370000104 -> dai.google.com master.m3u8, HTTP 200, 5098
'         bytes, 6 H.264/AAC variants (400x224 .. 1280x720).
'       stvp-USBD300002TU -> akamaized.net master.m3u8, HTTP 200, 1640
'         bytes, 5 variants. The backing CDN rotates per channel, so the
'         stream URL is always built per channel from LiveTvStreamUrl() and
'         never persisted as a hardcoded per-channel host.
'   EPG fallback (direct host, same verified bytes, fewer redirect hops):
'   https://raw.githubusercontent.com/matthuisman/i.mjh.nz/refs/heads/master/SamsungTVPlus/us.xml
'
' Poll the index at most daily. Channel IDs and backing hosts rotate, so the
' stream URL is always built per channel from LiveTvStreamUrl() and never
' persisted as a hardcoded per-channel host.
'
' GZIP RESEARCH NOTE (roUrlTransfer + gzip, per https://developer.roku.com/dev/docs/ifurltransfer):
'   roUrlTransfer.EnableEncodings(true) makes the transfer send
'   "Accept-Encoding: gzip" and transparently inflate a response that arrives
'   with "Content-Encoding: gzip". That covers a server that compresses on the
'   fly (e.g. requesting us.xml with gzip accepted).
'   It does NOT help with a static ".gz" file served as raw bytes with no
'   Content-Encoding header: verified 2026-09-19, the .gz feed arrives as
'   application/octet-stream gzip binary (magic 1f 8b, no Content-Encoding),
'   and BrightScript has no gunzip primitive, so such a payload is unusable
'   on-device. LiveTvTask.brs therefore NEVER requests a .gz URL: it fetches
'   the verified plain feeds and derives channels + EPG from them.
'   LiveTvLooksGzipped() stays as a tripwire shape-check (a proxy that ever
'   gzips a plain feed is reported as status 12/22 with a clear hint, never
'   parsed as garbage, never touched with Len/Instr unguarded).
'
' THREADING: pure functions, no SceneGraph dependency. roDateTime is used for
'   time math and is legal on any thread. All network I/O lives in
'   LiveTvTask.brs (never on the render thread). Nothing here touches the
'   registry: the lineup + EPG must NOT go in the 32KB registry. Caching is
'   in-memory (task fields) + tmp:/ files owned by LiveTvTask.brs.
'
' DEPENDENCIES: SafeGet / SafeStr (components/Tmdb.brs), JsonParseSafe
'   (components/Json.brs). Any component that includes this file must also
'   include those two scripts (see components/tasks/LiveTvTask.xml).
'
' All function names use the LiveTv prefix to avoid collisions with existing
' globals (SafeGet, SafeStr, JsonParseSafe, HttpGetText, Tmdb*, Febbox*,
' Vix*, RankCandidates, etc.).

' Canonical lineup source (verified 2026-09-19: HTTP 200, application/json,
' ~1.9MB, 582 US channels with real chno): the plain JSON index. The lineup
' is derived from its regions.us.channels map via LiveTvParseChannels(). If
' this index ever dies again (it 404'd in a previous round), the task falls
' back to the plain XMLTV feed and LiveTvParseChannelsFromXmltv().
function LiveTvChannelsUrl() as String
    return "https://i.mjh.nz/SamsungTVPlus/.channels.json"
end function

' Canonical EPG URL: the verified plain XMLTV feed (channels + guide share
' the same ID space, so one download serves the guide).
function LiveTvEpgUrl() as String
    return "https://i.mjh.nz/SamsungTVPlus/us.xml"
end function

' Plain-XML EPG endpoint (verified, same feed as LiveTvEpgUrl()).
function LiveTvEpgPlainUrl() as String
    return "https://i.mjh.nz/SamsungTVPlus/us.xml"
end function

' Direct-host fallback for the plain XMLTV feed (verified 2026-09-19: HTTP
' 200, text/plain, same bytes). Skips the i.mjh.nz -> github.com redirect
' hops when the primary is unreachable. Doubles as the lineup fallback body
' (parsed as XMLTV by LiveTvParseChannelsFromXmltv) when the JSON index is
' unreachable.
function LiveTvEpgFallbackUrl() as String
    return "https://raw.githubusercontent.com/matthuisman/i.mjh.nz/refs/heads/master/SamsungTVPlus/us.xml"
end function

' Build the playable HLS URL for a Samsung channel ID. The host is part of
' the sanctioned shape, not a hardcoded per-channel host: IDs rotate, so
' always rebuild via this function at play time.
function LiveTvStreamUrl(chanId as String) as String
    if chanId = invalid or chanId = "" then
        return ""
    end if
    return "https://jmp2.uk/stvp-" + chanId
end function

' Cap on curated channels so the cable grid stays fast.
function LiveTvMaxChannels() as Integer
    return 90
end function

' EPG window kept per channel: 6h back (in-progress shows) + 48h ahead.
function LiveTvEpgWindowPastSec() as Integer
    return 21600
end function

function LiveTvEpgWindowFutureSec() as Integer
    return 172800
end function

' Per-channel programme cap inside the window (bounds tmp:/ cache + field size).
function LiveTvMaxProgramsPerChannel() as Integer
    return 30
end function

' Global stored-programme cap when parsing without an allowlist.
function LiveTvMaxProgramsTotal() as Integer
    return 6000
end function

' Minimum seconds between network refreshes (daily poll).
function LiveTvCacheTtlSec() as Integer
    return 86400
end function

' Conservative group-name drop substrings (lowercase, Instr match against the
' "group" field). Group names in the wild are unverified, so this list stays
' short on purpose: name-dedup in LiveTvCurateChannels() already collapses
' market-duplicated regionals to a single entry. Tune here as needed.
function LiveTvDropGroupSubstrings() as Object
    return ["adult", "xxx", "porn", "religion", "religious", "church", "shopping"]
end function

' Best-effort gzip-magic sniff (0x1F 0x8B). The real gate is always a shape
' check (ParseJson regions / Instr <programme), see LiveTvParseChannels and
' LiveTvParseEpg, because string decoding can mask the magic bytes.
function LiveTvLooksGzipped(body as String) as Boolean
    if body = invalid or body = "" then
        return false
    end if
    if body.Len() < 2 then
        return false
    end if
    ' Global Mid() is 1-based (unlike the zero-based ifStringOps.Mid method):
    ' byte 2 lives at position 2.
    ' https://developer.roku.com/dev/docs/global-string-functions
    return Asc(Left(body, 1)) = 31 and Asc(Mid(body, 2, 1)) = 139
end function

' Lenient to-integer for JSON values that may arrive as Integer, Float or String.
function LiveTvToInt(v as Dynamic) as Integer
    if v = invalid then
        return 0
    end if
    t = type(v)
    if t = "Integer" or t = "roInt" then
        return v
    end if
    if t = "Float" or t = "roFloat" or t = "Double" or t = "roDouble" then
        return Int(v)
    end if
    if t = "String" or t = "roString" then
        ' ifStringOps.Trim() method form: bare Trim() is not a global function.
        s = v.Trim()
        if s = "" then
            return 0
        end if
        return s.ToInt()
    end if
    return 0
end function

' Current UTC epoch seconds. Legal on any thread (roDateTime is not a scene node).
function LiveTvNowSec() as Integer
    dt = CreateObject("roDateTime")
    return dt.AsSeconds()
end function

' Parse the JSON index body (.channels.json) into an array of channel records
' sorted by chNo: { id, title, thumbnail, url, epgId, genre, chNo,
' description, programs }.
' Shape verified 2026-09-19: { slug, regions: { us: { channels: { ID: { name,
' chno, logo, description, group, programs } } } } — chno is Samsung's real
' channel number, group the curated-genre drop key.
' programs IS used: each channel carries [[epoch,"Title"], ...] (present for
' all 581 US channels on 2026-09-26). It is the ONLY per-channel programme
' source that arrives with the lineup, so LiveTvLineupEpg() turns it into a
' now/next map the moment channels land. The XMLTV guide is still fetched
' afterwards for <desc> text, but it is a ~2.9MB string scan that does not
' always finish (see LiveTvLoadEpg), so it can no longer be the only path to
' a real "on now" title.
' Returns [] when the body is gzipped-binary, XML, or otherwise unparseable
' (use LiveTvLooksGzipped() to tell "still gzipped" apart from "bad payload").
function LiveTvParseChannels(body as String) as Object
    result = []
    if body = invalid or body = "" then
        return result
    end if
    if LiveTvLooksGzipped(body) then
        return result
    end if
    data = JsonParseSafe(body)
    if data = invalid or type(data) <> "roAssociativeArray" then
        return result
    end if
    regions = SafeGet(data, "regions", invalid)
    if regions = invalid or type(regions) <> "roAssociativeArray" then
        return result
    end if
    us = SafeGet(regions, "us", invalid)
    if us = invalid or type(us) <> "roAssociativeArray" then
        return result
    end if
    chanMap = SafeGet(us, "channels", invalid)
    if chanMap = invalid or type(chanMap) <> "roAssociativeArray" then
        return result
    end if
    for each chanId in chanMap
        entry = chanMap[chanId]
        if entry <> invalid and type(entry) = "roAssociativeArray" then
            title = SafeStr(entry, "name", "")
            if title <> "" then
                idStr = chanId.ToStr()
                progs = LiveTvLineupPrograms(entry)
                rec = {
                    id: idStr,
                    title: title,
                    thumbnail: SafeStr(entry, "logo", ""),
                    url: LiveTvStreamUrl(idStr),
                    epgId: idStr,
                    genre: SafeStr(entry, "group", ""),
                    chNo: LiveTvToInt(SafeGet(entry, "chno", 0)),
                    description: SafeStr(entry, "description", ""),
                    programs: progs
                }
                result.Push(rec)
            end if
        end if
    end for
    return LiveTvSortByChNo(result)
end function

' Turn one channel index entry's "programs" array ([[epoch, "Title"], ...])
' into the same { title, start, stop } shape LiveTvParseEpg produces, so the
' now/next consumer cannot tell where a programme came from.
' The feed lists upcoming start times only, so each block's end is the NEXT
' block's start; the final block gets a nominal 30 minutes (it can only ever
' be the "now" or a "next" tail entry, never a long in-progress read).
' Returns [] when the entry has no usable programs.
function LiveTvLineupPrograms(entry as Object) as Object
    out = []
    if entry = invalid then
        return out
    end if
    raw = SafeGet(entry, "programs", invalid)
    if raw = invalid or type(raw) <> "roArray" then
        return out
    end if
    for each item in raw
        ' Each item is a 2-element array [epoch, title]. Type-check the title
        ' by hand: SafeGet() calls .DoesExist(), which throws on a String.
        if item <> invalid and type(item) = "roArray" and item.count() >= 2 then
            startSec = LiveTvToInt(item[0])
            if startSec > 0 then
                titleStr = ""
                if type(item[1]) = "String" or type(item[1]) = "roString" then
                    titleStr = item[1].Trim()
                end if
                if titleStr <> "" then
                    prog = { title: titleStr, start: startSec }
                    prog["stop"] = startSec
                    out.Push(prog)
                end if
            end if
        end if
    end for
    if out.count() = 0 then
        return out
    end if
    out = LiveTvSortProgramsByStart(out)
    n = out.count()
    for i = 0 to n - 1
        endSec = 0
        if i < n - 1 then
            endSec = LiveTvToInt(SafeGet(out[i + 1], "start", 0))
        end if
        curStart = LiveTvToInt(SafeGet(out[i], "start", 0))
        if endSec <= curStart then
            endSec = curStart + 1800
        end if
        out[i]["stop"] = endSec
    end for
    cap = LiveTvMaxProgramsPerChannel()
    if out.count() > cap then
        trimmed = []
        for i = 0 to cap - 1
            trimmed.Push(out[i])
        end for
        out = trimmed
    end if
    return out
end function

' Build an EPG map in the exact LiveTvParseEpg contract
' ({ [chanId]: { programs, now, next } }) from the per-channel `programs`
' arrays already attached by LiveTvParseChannels.
'
' WHY: the XMLTV guide is a ~2.9MB string scanned with Instr from inside
' LiveTvParseEpg. On the 2026-09-26 device run the guide downloaded fine
' (HTTP 200, 2915256 bytes) but the task never reached its completion log and
' never raised an error, so the grid opened with epg=0 and every programme
' block fell back to its genre label. The channel index that the app ALREADY
' downloads and parses ships the same now/next start times, so build the map
' from it and the guide becomes a pure description upgrade instead of the
' single point of failure.
' Channels with no programs are simply absent, exactly like an unmatched feed.
' nowSec <= 0 selects the device clock (see LiveTvNowNext).
function LiveTvLineupEpg(channels as Object, nowSec as Integer) as Object
    epg = {}
    if channels = invalid or type(channels) <> "roArray" then
        return epg
    end if
    pivot = nowSec
    if pivot <= 0 then
        pivot = LiveTvNowSec()
    end if
    for each rec in channels
        if rec <> invalid and type(rec) = "roAssociativeArray" then
            list = SafeGet(rec, "programs", invalid)
            if list <> invalid and type(list) = "roArray" and list.count() > 0 then
                chanId = SafeStr(rec, "epgId", "")
                if chanId = "" then
                    chanId = SafeStr(rec, "id", "")
                end if
                if chanId <> "" then
                    snap = LiveTvNowNext(list, pivot)
                    epg[chanId] = { programs: list, now: snap.now, next: snap.next }
                end if
            end if
        end if
    end for
    return epg
end function

' Parse the channel lineup from XMLTV <channel> blocks in the plain us.xml
' feed. Fallback when the gzipped JSON index is unusable on-device
' (BrightScript has no gunzip primitive, so a still-gzipped body can never
' be parsed): display-name becomes the title, icon src the thumbnail, and
' the channel id feeds LiveTvStreamUrl() plus the EPG allowlist 1:1.
' chNo is synthetic document order (XMLTV carries no channel numbers), so
' the grid order matches the feed. Returns [] when no <channel> blocks exist.
function LiveTvParseChannelsFromXmltv(xmlBody as String) as Object
    result = []
    if xmlBody = invalid or xmlBody = "" then
        return result
    end if
    if Instr(1, xmlBody, "<channel") <= 0 then
        return result
    end if
    scanPos = 1
    guard = 0
    chNo = 0
    while true
        guard = guard + 1
        if guard > 5000 then
            exit while
        end if
        openAt = Instr(scanPos, xmlBody, "<channel")
        if openAt <= 0 then
            exit while
        end if
        ' Skip the "</channel>" closers: the char after "<channel" must be
        ' a space (attributes follow) or ">" (bare tag). Closers have "/".
        afterName = Mid(xmlBody, openAt + 8, 1)
        if afterName <> " " and afterName <> ">" then
            scanPos = openAt + 8
        else
            tagEnd = Instr(openAt, xmlBody, ">")
            if tagEnd <= 0 then
                exit while
            end if
            openTag = Mid(xmlBody, openAt, tagEnd - openAt + 1)
            chanId = LiveTvEpgAttr(openTag, "id")
            closeAt = Instr(tagEnd, xmlBody, "</channel>")
            if closeAt <= 0 then
                exit while
            end if
            if chanId <> "" then
                inner = Mid(xmlBody, tagEnd + 1, closeAt - tagEnd - 1)
                title = LiveTvEpgTagText(inner, "display-name")
                thumb = LiveTvParseXmltvIconSrc(inner)
                if title <> "" then
                    chNo = chNo + 1
                    idStr = chanId
                    rec = {
                        id: idStr,
                        title: title,
                        thumbnail: thumb,
                        url: LiveTvStreamUrl(idStr),
                        epgId: idStr,
                        genre: "",
                        chNo: chNo,
                        description: ""
                    }
                    result.Push(rec)
                end if
            end if
            scanPos = closeAt + 10
        end if
    end while
    return result
end function

' src of the first self-closing <icon .../> inside a <channel> body.
' LiveTvEpgTagText cannot serve here: <icon> never has a </icon> closer.
function LiveTvParseXmltvIconSrc(inner as String) as String
    if inner = invalid or inner = "" then
        return ""
    end if
    iconAt = Instr(1, inner, "<icon")
    if iconAt <= 0 then
        return ""
    end if
    iconEnd = Instr(iconAt, inner, ">")
    if iconEnd <= 0 then
        return ""
    end if
    iconTag = Mid(inner, iconAt, iconEnd - iconAt + 1)
    return LiveTvEpgAttr(iconTag, "src")
end function

' Insertion sort by numeric chNo (ascending). Channels without a number (0)
' sink to the top of the grid, which keeps them visible instead of lost.
function LiveTvSortByChNo(channels as Object) as Object
    if channels = invalid then
        return []
    end if
    n = channels.count()
    for i = 1 to n - 1
        keyRec = channels[i]
        keyNo = LiveTvToInt(SafeGet(keyRec, "chNo", 0))
        j = i - 1
        while j >= 0 and LiveTvToInt(SafeGet(channels[j], "chNo", 0)) > keyNo
            channels[j + 1] = channels[j]
            j = j - 1
        end while
        channels[j + 1] = keyRec
    end for
    return channels
end function

' Curate a raw parsed lineup down to grid size: dedupe by normalized title
' (input is chNo-sorted, so the lowest channel number wins and regional
' duplicates collapse to one entry), drop conservative groups, cap the count.
' maxCount <= 0 selects LiveTvMaxChannels().
function LiveTvCurateChannels(all as Object, maxCount as Integer) as Object
    result = []
    if all = invalid then
        return result
    end if
    capCount = maxCount
    if capCount <= 0 then
        capCount = LiveTvMaxChannels()
    end if
    seen = {}
    drops = LiveTvDropGroupSubstrings()
    for each rec in all
        if rec <> invalid and type(rec) = "roAssociativeArray" then
            title = SafeStr(rec, "title", "")
            if title <> "" then
                normTitle = LCase(title.Trim())
                if not seen.DoesExist(normTitle) then
                    genre = LCase(SafeStr(rec, "genre", ""))
                    dropIt = false
                    for each bad in drops
                        if genre <> "" and Instr(1, genre, bad) > 0 then
                            dropIt = true
                        end if
                    end for
                    if not dropIt then
                        seen[normTitle] = true
                        result.Push(rec)
                        if result.count() >= capCount then
                            exit for
                        end if
                    end if
                end if
            end if
        end if
    end for
    return result
end function

' Build an O(1) allowlist AA ({ epgId: true }) from curated channels for the
' EPG parser so programmes for unwanted channels are skipped without allocs.
function LiveTvWantedIds(channels as Object) as Object
    wanted = {}
    if channels = invalid then
        return wanted
    end if
    for each rec in channels
        if rec <> invalid and type(rec) = "roAssociativeArray" then
            idStr = SafeStr(rec, "epgId", "")
            if idStr = "" then
                idStr = SafeStr(rec, "id", "")
            end if
            if idStr <> "" then
                wanted[idStr] = true
            end if
        end if
    end for
    return wanted
end function

' Convert an XMLTV timestamp ("yyyyMMddHHmmss +zzzz", "T"/space separators
' tolerated, offset optional and assumed UTC when absent) to epoch seconds.
' Returns 0 when invalid. Field ranges are validated BEFORE FromISO8601String
' because a failed parse would leave "now" in the roDateTime object.
function LiveTvXmltvToEpoch(ts as String) as Integer
    if ts = invalid or ts = "" then
        return 0
    end if
    s = ts.Trim()
    digits = ""
    for i = 1 to s.Len()
        ch = Mid(s, i, 1)
        code = Asc(ch)
        if code >= 48 and code <= 57 then
            digits = digits + ch
        end if
    end for
    if digits.Len() < 14 then
        return 0
    end if
    datePart = Left(digits, 8)
    timePart = Mid(digits, 9, 6)
    mo = Mid(datePart, 5, 2).ToInt()
    dy = Mid(datePart, 7, 2).ToInt()
    hh = Left(timePart, 2).ToInt()
    mm = Mid(timePart, 3, 2).ToInt()
    ss = Mid(timePart, 5, 2).ToInt()
    if mo < 1 or mo > 12 then
        return 0
    end if
    if dy < 1 or dy > 31 then
        return 0
    end if
    if hh > 23 or mm > 59 or ss > 61 then
        return 0
    end if
    iso = Left(datePart, 4) + "-" + Mid(datePart, 5, 2) + "-" + Mid(datePart, 7, 2) + "T" + Left(timePart, 2) + ":" + Mid(timePart, 3, 2) + ":" + Mid(timePart, 5, 2) + "Z"
    dt = CreateObject("roDateTime")
    dt.FromISO8601String(iso)
    epoch = dt.AsSeconds()
    if epoch <= 0 then
        return 0
    end if
    ' Trailing numeric offset (last 4+ digits past the 14-digit wall time) with
    ' its sign taken from the raw string, e.g. "-0500" shifts wall time to UTC.
    if digits.Len() >= 18 then
        signIdx = 0
        k = s.Len()
        while k > 0
            c = Mid(s, k, 1)
            if c = "+" or c = "-" then
                signIdx = k
                exit while
            end if
            k = k - 1
        end while
        if signIdx > 0 then
            offDigits = ""
            for m = signIdx + 1 to s.Len()
                ck = Mid(s, m, 1)
                ckCode = Asc(ck)
                if ckCode >= 48 and ckCode <= 57 then
                    offDigits = offDigits + ck
                end if
            end for
            if offDigits.Len() >= 4 then
                offH = Left(offDigits, 2).ToInt()
                offM = Mid(offDigits, 3, 2).ToInt()
                adjSec = offH * 3600 + offM * 60
                if Mid(s, signIdx, 1) = "-" then
                    adjSec = 0 - adjSec
                end if
                return epoch - adjSec
            end if
        end if
    end if
    return epoch
end function

' Read attribute attrName from a single open tag (e.g. channel/start/stop).
function LiveTvEpgAttr(tag as String, attrName as String) as String
    if tag = invalid or tag = "" then
        return ""
    end if
    if attrName = invalid or attrName = "" then
        return ""
    end if
    key = attrName + "=" + Chr(34)
    at = Instr(1, tag, key)
    if at <= 0 then
        return ""
    end if
    valStart = at + key.Len()
    endQuote = Instr(at + key.Len(), tag, Chr(34))
    if endQuote <= 0 then
        return ""
    end if
    return Mid(tag, valStart, endQuote - valStart)
end function

' Text of the first <tagName[ ...]>...</tagName> inside an element body,
' XML-entity decoded. Returns "" when absent.
function LiveTvEpgTagText(inner as String, tagName as String) as String
    if inner = invalid or inner = "" then
        return ""
    end if
    openAt = Instr(1, inner, "<" + tagName)
    if openAt <= 0 then
        return ""
    end if
    gt = Instr(openAt, inner, ">")
    if gt <= 0 then
        return ""
    end if
    closeTag = "</" + tagName + ">"
    closeAt = Instr(gt, inner, closeTag)
    if closeAt <= 0 then
        return ""
    end if
    raw = Mid(inner, gt + 1, closeAt - gt - 1)
    return LiveTvXmlUnescape(raw.Trim())
end function

' Decode the 5 named XML entities plus numeric refs (&#39; &#x27; ...).
' "&amp;" is decoded first so double-escaped sequences resolve correctly.
function LiveTvXmlUnescape(s as String) as String
    if s = invalid or s = "" then
        return ""
    end if
    out = s.Replace("&amp;", "&")
    out = out.Replace("&lt;", "<")
    out = out.Replace("&gt;", ">")
    out = out.Replace("&quot;", Chr(34))
    out = out.Replace("&apos;", "'")
    start = Instr(1, out, "&#")
    guard = 0
    while start > 0 and guard < 50
        guard = guard + 1
        semi = Instr(start + 2, out, ";")
        if semi <= 0 or semi - start > 8 then
            exit while
        end if
        numStr = Mid(out, start + 2, semi - start - 2)
        code = 0
        if Left(numStr, 1) = "x" or Left(numStr, 1) = "X" then
            ' Global Mid() is 1-based: the hex digits start at position 2
            ' (e.g. "x27" -> "27" -> 39). A 2-arg Mid() reads to end of string.
            code = LiveTvHexToInt(Mid(numStr, 2))
        else
            code = LiveTvToInt(numStr)
        end if
        if code > 0 and code < 256 then
            out = Left(out, start - 1) + Chr(code) + Mid(out, semi + 1)
        else if code >= 256 then
            out = Left(out, start - 1) + "?" + Mid(out, semi + 1)
        else
            exit while
        end if
        start = Instr(start + 1, out, "&#")
    end while
    return out
end function

' Small hex parser for &#x..; refs. Returns 0 when invalid.
function LiveTvHexToInt(hexStr as String) as Integer
    if hexStr = invalid or hexStr = "" then
        return 0
    end if
    total = 0
    for i = 1 to hexStr.Len()
        ch = Mid(hexStr, i, 1)
        code = Asc(ch)
        digit = -1
        if code >= 48 and code <= 57 then
            digit = code - 48
        else if code >= 65 and code <= 70 then
            digit = code - 55
        else if code >= 97 and code <= 102 then
            digit = code - 87
        end if
        if digit < 0 then
            return 0
        end if
        total = total * 16 + digit
    end for
    return total
end function

' Parse XMLTV with a lean string scan (no DOM: the plain feed is ~3MB and a
' full roXMLElement tree would be slow and memory-heavy). Only <programme>
' blocks for wanted channels inside [now-6h, now+48h] are materialized.
'
' wantedIds: allowlist AA from LiveTvWantedIds(), or invalid to accept every
'   channel (capped by LiveTvMaxProgramsTotal()).
' nowSec <= 0 selects the device clock via LiveTvNowSec().
'
' Returns an AA keyed by channel id. Each entry is a superset of the grid
' contract { now: { title, start, stop }, next: [...] } with the windowed
' programme list attached for recompute without refetch:
'   { programs: [{ title, start, stop, desc } ...] (start-sorted),
'     now: { title, start, stop },
'     next: [{ title, start, stop } ...] (max 2) }
' NOTE: "stop" is written via bracket assignment so the BrightScript
' reserved word `stop` never appears as a literal AA key.
function LiveTvParseEpg(xmlBody as String, wantedIds as Object, nowSec as Integer) as Object
    epg = {}
    if xmlBody = invalid or xmlBody = "" then
        return epg
    end if
    if Instr(1, xmlBody, "<programme") <= 0 then
        return epg
    end if
    pivot = nowSec
    if pivot <= 0 then
        pivot = LiveTvNowSec()
    end if
    pastCut = pivot - LiveTvEpgWindowPastSec()
    futureCut = pivot + LiveTvEpgWindowFutureSec()
    maxPerChan = LiveTvMaxProgramsPerChannel()
    maxTotal = LiveTvMaxProgramsTotal()
    total = 0
    scanPos = 1
    guard = 0
    while true
        guard = guard + 1
        if guard > 60000 then
            exit while
        end if
        openAt = Instr(scanPos, xmlBody, "<programme")
        if openAt <= 0 then
            exit while
        end if
        tagEnd = Instr(openAt, xmlBody, ">")
        if tagEnd <= 0 then
            exit while
        end if
        openTag = Mid(xmlBody, openAt, tagEnd - openAt + 1)
        chanId = LiveTvEpgAttr(openTag, "channel")
        takeIt = true
        if chanId = "" then
            takeIt = false
        else if wantedIds <> invalid and not wantedIds.DoesExist(chanId) then
            takeIt = false
        end if
        closeAt = Instr(tagEnd, xmlBody, "</programme>")
        if closeAt <= 0 then
            exit while
        end if
        if takeIt then
            startSec = LiveTvXmltvToEpoch(LiveTvEpgAttr(openTag, "start"))
            stopSec = LiveTvXmltvToEpoch(LiveTvEpgAttr(openTag, "stop"))
            if startSec > 0 and stopSec > startSec and stopSec > pastCut and startSec < futureCut then
                inner = Mid(xmlBody, tagEnd + 1, closeAt - tagEnd - 1)
                title = LiveTvEpgTagText(inner, "title")
                desc = LiveTvEpgTagText(inner, "desc")
                if desc.Len() > 180 then
                    desc = Left(desc, 180) + "..."
                end if
                prog = { title: title, start: startSec, desc: desc }
                prog["stop"] = stopSec
                bucket = epg[chanId]
                if bucket = invalid then
                    bucket = []
                    epg[chanId] = bucket
                end if
                if bucket.count() < maxPerChan and total < maxTotal then
                    bucket.Push(prog)
                    total = total + 1
                end if
            end if
        end if
        scanPos = closeAt + 12
    end while
    for each chanKey in epg
        list = epg[chanKey]
        LiveTvSortProgramsByStart(list)
        snap = LiveTvNowNext(list, pivot)
        entry = { programs: list, now: snap.now, next: snap.next }
        epg[chanKey] = entry
    end for
    return epg
end function

' Insertion sort of a programme list by numeric start (ascending, in place).
function LiveTvSortProgramsByStart(list as Object) as Object
    if list = invalid then
        return []
    end if
    n = list.count()
    for i = 1 to n - 1
        keyProg = list[i]
        keyStart = LiveTvToInt(SafeGet(keyProg, "start", 0))
        j = i - 1
        while j >= 0 and LiveTvToInt(SafeGet(list[j], "start", 0)) > keyStart
            list[j + 1] = list[j]
            j = j - 1
        end while
        list[j + 1] = keyProg
    end for
    return list
end function

' Compute now/next from a start-sorted programme list at pivot epoch seconds.
' nowSec <= 0 selects the device clock. Returns
'   { now: { title, start, stop }, next: [{ title, start, stop } x up to 2] }
' with an empty-title `now` when nothing covers the pivot (gap in schedule).
function LiveTvNowNext(programs as Object, nowSec as Integer) as Object
    blank = { title: "", start: 0 }
    blank["stop"] = 0
    result = { now: blank, next: [] }
    if programs = invalid then
        return result
    end if
    pivot = nowSec
    if pivot <= 0 then
        pivot = LiveTvNowSec()
    end if
    for each prog in programs
        if prog <> invalid and type(prog) = "roAssociativeArray" then
            pStart = LiveTvToInt(SafeGet(prog, "start", 0))
            pStop = LiveTvToInt(SafeGet(prog, "stop", 0))
            if pStart > 0 and pStop > pStart then
                if pStart <= pivot and pivot < pStop then
                    cur = { title: SafeStr(prog, "title", ""), start: pStart }
                    cur["stop"] = pStop
                    result.now = cur
                else if pStart > pivot and result.next.count() < 2 then
                    upNext = { title: SafeStr(prog, "title", ""), start: pStart }
                    upNext["stop"] = pStop
                    result.next.Push(upNext)
                end if
            end if
        end if
    end for
    return result
end function

' Recompute now/next for a programme list at the wall clock.
'
' The epg map hands each channel a { now, next } SNAPSHOT taken when the
' guide was merged. A live screen that prints that snapshot is only correct
' for the first programme: once it ends, "now" is a finished show and
' "next" is the show that is actually on air - which is exactly the stale
' "up next" card the user reported. This walks the same programme list at
' the current clock instead, so nothing can go stale.
'
' Returns { now, next, next2 } with blanks (title "") when nothing covers or
' follows the pivot. next2 is unused on screen today but free to compute and
' keeps the door open for a "later" row.
function LiveTvNowNextAt(programs as Object, pivot as Integer) as Object
    blank = { title: "", start: 0, desc: "" }
    blank["stop"] = 0
    out = { now: blank, next: blank, next2: blank }
    if programs = invalid or type(programs) <> "roArray" then return out
    if pivot <= 0 then pivot = LiveTvNowSec()
    nowBest = invalid
    nextBest = invalid
    next2Best = invalid
    for each p in programs
        if p <> invalid and type(p) = "roAssociativeArray" then
            ps = LiveTvToInt(SafeGet(p, "start", 0))
            pe = LiveTvToInt(SafeGet(p, "stop", 0))
            if ps > 0 and pe > ps then
                if ps <= pivot and pivot < pe then
                    ' Latest start wins if two entries overlap (the guide
                    ' sometimes ships a padded copy of the same programme).
                    if nowBest = invalid or ps > LiveTvToInt(SafeGet(nowBest, "start", 0)) then
                        nowBest = p
                    end if
                else if ps > pivot then
                    if nextBest = invalid or ps < LiveTvToInt(SafeGet(nextBest, "start", 0)) then
                        next2Best = nextBest
                        nextBest = p
                    else if next2Best = invalid or ps < LiveTvToInt(SafeGet(next2Best, "start", 0)) then
                        next2Best = p
                    end if
                end if
            end if
        end if
    end for
    if nowBest <> invalid then out.now = nowBest
    if nextBest <> invalid then out.next = nextBest
    if next2Best <> invalid then out.next2 = next2Best
    return out
end function

' ------------------------------------------------------------------
' Genre rail (2026-09-23 redesign): the left panel lists canonical
' genres instead of a raw channel grid. Free lineups map Samsung's 19
' messy "group" strings (verified live 2026-09-23: Sports & Outdoors 53,
' Music 49, Action & Drama 42, Latino 42, Kids 40, Home & Food 38, ...)
' into ~10 clean buckets; the premium (cinevid) lineup keeps its own
' category strings which already match the bucket labels. "all" and
' "premium" are synthetic rail entries: "all" = the whole free lineup,
' "premium" = the cinevid lineup (its own genre, per user request).
' ------------------------------------------------------------------

' Ordered canonical genres for the left rail. ids are stable strings used
' in state + filtering; labels are what the rail renders. The rail hides any
' genre whose count is 0 (see LiveTvRailDefs' consumer), so this list can be
' generous: a bucket that the current feed does not fill simply does not show.
function LiveTvCanonicalGenres() as Object
    return [
        { id: "sudo", label: "Sudo Movies" },
        { id: "all", label: "All Channels" },
        ' Premium (cinevid) is switched OFF for now: the index is unreachable
        ' from the device (status=11 on every fetch), so the rail entry only
        ' ever produced an empty bucket plus a failed background task. The
        ' cinevid plumbing lower down is deliberately left intact so the
        ' bucket can be switched back on by re-adding this one line.
        { id: "movies", label: "Movies" },
        { id: "sports", label: "Sports" },
        { id: "news", label: "News" },
        { id: "kids", label: "Kids" },
        { id: "documentary", label: "Documentary" },
        { id: "comedy", label: "Comedy" },
        { id: "drama", label: "Drama" },
        { id: "reality", label: "Reality" },
        { id: "scifi", label: "Sci-Fi" },
        { id: "anime", label: "Anime" },
        { id: "classic", label: "Classic TV" },
        { id: "talk", label: "Talk" },
        { id: "music", label: "Music" },
        { id: "lifestyle", label: "Lifestyle" },
        { id: "latino", label: "Latino" },
        { id: "weather", label: "Weather" },
        { id: "entertainment", label: "Entertainment" }
    ]
end function

' True for the rail entries that are VIEWS or synthetic groupings rather than
' a genre bucket (they are never hidden for having zero channels).
function LiveTvIsSyntheticGenre(genreId as String) as Boolean
    return genreId = "all" or genreId = "premium" or genreId = "sudo" or genreId = "grid"
end function

' Map a raw Samsung "group" string to a canonical genre id (see
' LiveTvCanonicalGenres). Substring matching keeps it robust to feed
' wording drift; anything unknown (including "") falls back to
' "entertainment" so no channel ever disappears from the rail.
' Verified mapping against the live 2026-09-23 feed:
'   Sports & Outdoors + Motor Sports -> sports
'   News & Opinion -> news | Movies -> movies | Kids -> kids
'   Nature, History & Science -> documentary | Music -> music
'   Home & Food + Ambiance -> lifestyle | Latino -> latino
'   Action & Drama -> drama | Comedy -> comedy
'   Reality TV / Reality Competition / Game Shows -> reality
'   Sci-Fi & Horror -> scifi | Anime & Gaming -> anime
'   Western & Classic TV -> classic | Talk Shows -> talk
'   Lifestyle & Pop Culture -> lifestyle
' Order matters: the most specific phrase wins (checked first, not last),
' so "Nature, History & Science" cannot be stolen by the "kids" bucket.
function LiveTvGenreFromGroup(group as String) as String
    if group = invalid then
        return "entertainment"
    end if
    g = LCase(group.Trim())
    if g = "" then
        return "entertainment"
    end if
    if Instr(1, g, "sport") > 0 or Instr(1, g, "motor") > 0 then
        return "sports"
    end if
    if Instr(1, g, "news") > 0 then
        return "news"
    end if
    if Instr(1, g, "weather") > 0 then
        return "weather"
    end if
    if Instr(1, g, "kid") > 0 or Instr(1, g, "family") > 0 or Instr(1, g, "cartoon") > 0 or Instr(1, g, "toon") > 0 then
        return "kids"
    end if
    if Instr(1, g, "anime") > 0 or Instr(1, g, "gaming") > 0 then
        return "anime"
    end if
    if Instr(1, g, "sci") > 0 or Instr(1, g, "horror") > 0 then
        return "scifi"
    end if
    if Instr(1, g, "comedy") > 0 then
        return "comedy"
    end if
    if Instr(1, g, "drama") > 0 or Instr(1, g, "action") > 0 then
        return "drama"
    end if
    if Instr(1, g, "reality") > 0 or Instr(1, g, "game show") > 0 or Instr(1, g, "competition") > 0 then
        return "reality"
    end if
    if Instr(1, g, "classic") > 0 or Instr(1, g, "western") > 0 then
        return "classic"
    end if
    if Instr(1, g, "talk") > 0 then
        return "talk"
    end if
    if Instr(1, g, "nature") > 0 or Instr(1, g, "history") > 0 or Instr(1, g, "science") > 0 or Instr(1, g, "documentary") > 0 then
        return "documentary"
    end if
    if Instr(1, g, "movie") > 0 or Instr(1, g, "film") > 0 or Instr(1, g, "cinema") > 0 then
        return "movies"
    end if
    if Instr(1, g, "music") > 0 then
        return "music"
    end if
    if Instr(1, g, "home") > 0 or Instr(1, g, "food") > 0 or Instr(1, g, "ambiance") > 0 or Instr(1, g, "lifestyle") > 0 or Instr(1, g, "pop culture") > 0 then
        return "lifestyle"
    end if
    if Instr(1, g, "latino") > 0 or Instr(1, g, "spanish") > 0 then
        return "latino"
    end if
    return "entertainment"
end function

' Normalize any raw genre string to a canonical id. Cinevid premium records
' carry their own category vocabulary ("Action", "Sci-Fi", "Classic"), so
' pass those through the same matcher instead of trusting them to be ids.
function LiveTvNormalizeGenreId(raw as String) as String
    if raw = invalid then
        return "entertainment"
    end if
    g = LCase(raw.Trim())
    if g = "" then
        return "entertainment"
    end if
    for each def in LiveTvCanonicalGenres()
        if def.id = g then
            return g
        end if
    end for
    return LiveTvGenreFromGroup(g)
end function

' Canonical genre id for a channel record: premium records carry their
' cinevid category in `genre` (already canonical, case aside); free
' records carry the raw Samsung group and are mapped here. Result is
' memoized on the record (`genreId` field) so cached tmp:/ lineups from
' older builds get mapped once, not per keystroke.
function LiveTvGenreIdOf(ch as Object) as String
    if ch = invalid or type(ch) <> "roAssociativeArray" then
        return "entertainment"
    end if
    memo = SafeStr(ch, "genreId", "")
    if memo <> "" then
        return memo
    end if
    if SafeStr(ch, "source", "") = "cinevid" then
        ' Premium categories use their own vocabulary, so normalize them
        ' through the same matcher instead of trusting them to be ids.
        gid = LiveTvNormalizeGenreId(SafeStr(ch, "genre", ""))
    else if SafeStr(ch, "source", "") = "sudo" then
        ' Sudo Movies records carry genre "Sudo Movies", which would map to
        ' "movies" via substring match below - keep them in their own rail.
        gid = "sudo"
    else
        gid = LiveTvGenreFromGroup(SafeStr(ch, "genre", ""))
    end if
    ch.genreId = gid
    return gid
end function

' Normalized matching key: lowercase, alphanumerics only. Both lineups
' derive from Samsung's guide data, so names match after normalization
' ("HappyKids" == "HappyKids"; accents are stripped consistently on BOTH
' sides since the normalized key keeps only [a-z0-9]).
function LiveTvStvgNormKey(name as String) as String
    if name = invalid then return ""
    s = LCase(name)
    out = ""
    for i = 1 to s.Len()
        ch = Mid(s, i, 1)
        code = Asc(ch)
        if (code >= 48 and code <= 57) or (code >= 97 and code <= 122) then
            out = out + ch
        end if
    end for
    return out
end function
