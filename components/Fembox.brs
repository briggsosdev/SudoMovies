' Decode a base64 string into a string of raw bytes. Pure BrightScript, no JS.
' Handles standard base64; JWT uses base64url which is converted before calling.
function FebboxB64Decode(b64 as String) as String
    valid = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    out = ""
    buf = 0
    bits = 0
    for i = 1 to b64.Len()
        ' ifStringOps.Mid() is zero-based (unlike global Mid(), 1-based).
        ' https://developer.roku.com/dev/docs/ifstringops
        ch = b64.Mid(i - 1, 1)
        if ch = "=" then
            exit for
        end if
        idx = Instr(1, valid, ch)
        if idx > 0 then
            v = idx - 1
            buf = buf * 64 + v
            bits = bits + 6
            if bits >= 8 then
                bits = bits - 8
                byteVal = (buf \ (2 ^ bits)) AND 255
                buf = buf MOD (2 ^ bits)
                out = out + Chr(byteVal)
            end if
        end if
    end for
    return out
end function

' Base64url -> string (convert -/_ to +// and pad, then decode).
function FebboxB64UrlToString(input as String) as String
    s = input
    s = s.Replace("-", "+")
    s = s.Replace("_", "/")
    while s.Len() MOD 4 <> 0
        s = s + "="
    end while
    return FebboxB64Decode(s)
end function

' Extract the "exp" claim (unix seconds) from a Febbox JWT, or 0 if absent.
function FebboxJwtExp(token as String) as Integer
    if token = invalid or token = "" then
        return 0
    end if
    p1 = Instr(1, token, ".")
    if p1 = 0 then
        return 0
    end if
    p2 = Instr(p1 + 1, token, ".")
    if p2 = 0 then
        return 0
    end if
    payload = Mid(token, p1 + 1, p2 - p1 - 1)
    if payload = "" then
        return 0
    end if
    dec = FebboxB64UrlToString(payload)
    pat = Chr(34) + "exp" + Chr(34) + ":"
    i = Instr(1, dec, pat)
    if i = 0 then
        return 0
    end if
    j = i + Len(pat)
    num = ""
    ' j is a 1-based global-Instr position; method Mid() is zero-based.
    while j <= dec.Len() and dec.Mid(j - 1, 1) >= "0" and dec.Mid(j - 1, 1) <= "9"
        num = num + dec.Mid(j - 1, 1)
        j = j + 1
    end while
    if num = "" then
        return 0
    end if
    return num.toInt()
end function

' True when the token's exp has already passed.
function FebboxTokenExpired(token as String) as Boolean
    exp = FebboxJwtExp(token)
    if exp = 0 then
        return false
    end if
    now = CreateObject("roDateTime").AsSeconds()
    return exp < now
end function

function FemboxMovieUrl(tmdbId as String, token as String) as String
    c = AppConstants()
    return c.femboxBase + "/movie/" + tmdbId + "?ui=" + UrlEncode(token)
end function

function _FemboxEpisodeUrl(tmdbId as String, seasonNum as Integer, episodeNum as Integer, token as String) as String
    c = AppConstants()
    return c.femboxBase + "/tv/" + tmdbId + "/" + seasonNum.ToStr() + "/" + episodeNum.ToStr() + "?ui=" + UrlEncode(token)
end function

' Normalizes a fembox/aether FEM response into playable candidates.
' Supported shapes (kept deliberately loose):
'   { links:  [ { url, quality, headers?, subtitle? } ] }
'   { sources:[ same ] }
'   { qualities: { "1080": { url, ... }, ... } }
'   { stream: "direct url" } / { url: "direct url" }
function FemboxParseCandidates(body as String) as Object
    result = []
    data = JsonParseSafe(body)
    if data = invalid then
        return result
    end if

    links = SafeGet(data, "links", invalid)
    if links = invalid then
        links = SafeGet(data, "sources", invalid)
    end if
    if type(links) = "roAssociativeArray" then
        ' qualities map: q -> { url }
        flat = []
        for each q in links
            item = links[q]
            if type(item) = "roAssociativeArray" then
                if item.url = invalid then
                    item.url = ""
                end if
                if item.quality = invalid then
                    item.quality = q
                end if
                flat.Push(item)
            end if
        end for
        links = flat
    end if

    if type(links) <> "roArray" then
        links = []
    end if

    subsRaw = SafeGet(data, "subtitles", [])
    subAttach = []
    try
        if type(subsRaw) = "roArray" then
            for each s in subsRaw
                if type(s) = "roAssociativeArray" then
                    su = SafeStr(s, "url", "")
                    if su <> "" then
                        lang = SafeStr(s, "language", "")
                        label = SafeStr(s, "name", "")
                        if label = "" then
                            label = lang
                        end if
                        subAttach.Push({ url: su, lang: lang, label: label })
                    end if
                end if
            end for
        end if
    catch e
        ? "FEM subtitles parse issue: " + e.Message
    end try

    for each item in links
        if type(item) <> "roAssociativeArray" then
            ? "FEM skip non-object source"
        else
            try
                url = SafeStr(item, "url", "")
                if type(url) <> "roString" and type(url) <> "String" then
                    url = ""
                end if
                if url <> "" then
                cand = {
                    url: url,
                    quality: SafeStr(item, "quality", SafeStr(item, "qualityLabel", "")),
                    label: "",
                    headers: {},
                    subtitles: [],
                    format: "file",
                    size: SafeStr(item, "size", ""),
                    score: 0,
                }
                if cand.quality = "" then
                    cand.quality = SafeStr(item, "name", "")
                end if
                if cand.quality = "" then
                    cand.quality = SafeStr(item, "qualityName", "")
                end if
                lo = LCase(url)
                if Instr(1, lo, ".m3u8") > 0 then
                    cand.format = "hls"
                end if
                h = SafeGet(item, "headers", {})
                if type(h) = "roAssociativeArray" then
                    merged = {}
                    for each k in h
                        merged[k] = SafeStr(h, k, "")
                    end for
                    cand.headers = merged
                end if
                subv = SafeStr(item, "subtitle", SafeStr(item, "subtitles", ""))
                if subv <> "" then
                    if Left(subv, 1) = "/" then
                        subv = AppConstants().femboxBase + subv
                    end if
                    cand.subtitles.Push({ url: subv, lang: "en", label: "English" })
                end if
                if cand.subtitles.count() = 0 and subAttach.count() > 0 then
                    cand.subtitles = subAttach
                end if
                result.Push(cand)
                end if
            catch e
                ? "FEM skip bad source: " + e.Message
            end try
        end if
    end for

    ? "FEM parsed=" + result.count().ToStr()

    if result.count() = 0 then
        stream = SafeGet(data, "stream", invalid)
        if stream = invalid then
            stream = SafeGet(data, "url", "")
        end if
        if type(stream) = "roString" and stream <> "" then
            cand = {
                url: stream,
                quality: "",
                label: "Stream",
                headers: {},
                subtitles: [],
                format: "file",
                score: 0,
            }
            lo = LCase(stream)
            if Instr(1, lo, ".m3u8") > 0 then
                cand.format = "hls"
            end if
            result.Push(cand)
        end if
    end if

    return result
end function