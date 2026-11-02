' UrbanStreams.brs — helpers for urban type streams from external sources.
'
' Usage: included ONLY by components/tasks/UrbanTask.xml (task thread).
' Never include this file in a render-thread component: roUrlTransfer is
' illegal on the render thread. Configure the source URL via Config.brs: urbanApiBase (set in ConfigLoad()).
'
' All function names use the Urban prefix to avoid collisions (SafeGet, SafeStr,
' JsonParseSafe, HttpGetText, Tmdb*, Febbox*, Vix*, RankCandidates, etc.).
'

function UrbanHost() as String
    return "https://brokensilenze.mom"
end function

' Canonical lineup endpoint.
function UrbanChannelsUrl() as String
    return UrbanHost() + "/api/channels"
end function

' Parse the channels index body into scene-shaped records:
'   { id, title, thumbnail, url: "", epgId: "", genre: category, chNo: n,
'     description: "", source: "urban" }
' Returns [] when the body is not the expected JSON shape.
function UrbanParseChannels(body as String) as Object
    result = []
    if body = invalid or body = "" then
        return result
    end if
    data = JsonParseSafe(body)
    if data = invalid or type(data) <> "roAssociativeArray" then
        return result
    end if
    chans = SafeGet(data, "channels", invalid)
    if chans = invalid or type(chans) <> "roArray" then
        return result
    end if
    for each entry in chans
        if entry <> invalid and type(entry) = "roAssociativeArray" then
            title = SafeStr(entry, "name", "")
            if title <> "" then
                idStr = SafeStr(entry, "id", "")
                if idStr <> "" then
                    thumbnail = SafeStr(entry, "logo", "")
                    genre = SafeStr(entry, "category", "")
                    desc = SafeStr(entry, "description", "")
                    result.Push({
                        id: idStr,
                        title: title,
                        thumbnail: thumbnail,
                        url: "",
                        epgId: "",
                        genre: genre,
                        chNo: 0,
                        description: desc,
                        source: "urban"
                    })
                end if
            end if
        end if
    end for
    return result
end function

' Fetch the urban channels index and return the parsed array, or invalid after
' setting status/errorDetail (terminal failure).
function UrbanLoadChannels() as Dynamic
    url = UrbanChannelsUrl()
    if url = "" then
        m.top.errorDetail = "Urban streams: missing API base URL in config"
        m.top.status = 11
        return invalid
    end if
    res = HttpGetText(url, {})
    if res.status <> 200 then
        m.top.errorDetail = "Urban streams unreachable (HTTP " + res.status.ToStr() + ") - check your network connection, then press BACK and retry"
        m.top.status = 11
        return invalid
    end if
    if not IsString(res.body) then
        m.top.errorDetail = "Urban streams unparseable: unexpected body type - press BACK and retry later"
        m.top.status = 12
        return invalid
    end if
    if res.body.Len() = 0 then
        m.top.errorDetail = "Urban streams empty: received empty body - press BACK and retry later"
        m.top.status = 12
        return invalid
    end if
    parsed = UrbanParseChannels(res.body)
    if parsed.count() = 0 then
        m.top.errorDetail = "Urban streams unparseable: no usable channels in the index (feed shape changed) - press BACK and retry later"
        m.top.status = 12
        return invalid
    end if
    ? "URBAN lineup curated=" + parsed.count().ToStr()
    return parsed
end function

' Convenience: urban genre from a raw group string (case-insensitive substring).
function UrbanGenreFromGroup(group as String) as String
    if group = invalid then
        return "entertainment"
    end if
    g = LCase(group.Trim())
    if g = "" then
        return "entertainment"
    end if
    if Instr(1, g, "urban") > 0 then
        return "urban"
    end if
    if Instr(1, g, "hip hop") > 0 or Instr(1, g, "rap") > 0 then
        return "urban"
    end if
    if Instr(1, g, "rnb") > 0 then
        return "urban"
    end if
    return "entertainment"
end function

' ===========================================================================
' VIDEO RESOLUTION SUPPORT
' ===========================================================================
' Attempt to resolve a playable video URL for an urban channel.
' Tries multiple embed services in sequence; returns first successful URL or "".
function UrbanResolveVideo(channel as Object, episodeTitle as String) as String
    url = ""
    genre = LCase(SafeStr(channel, "genre", ""))
    title = SafeStr(channel, "title", "")
    if title = "" then return ""

    ' Build search-friendly query from title + episode info.
    query = LCase(title + " " + episodeTitle)
    query = UrbanReplaceString(query, " ", "+")
    ' The apostrophe argument used to be lost in an encoding round-trip,
    ' arriving as "" - UrbanReplaceString returns the input unchanged for an
    ' empty needle, so the call was a silent no-op. Restored so titles with
    ' an apostrophe produce a valid query string.
    query = UrbanReplaceString(query, "'", "%27")

    ' Try Vidlox embed resolver
    url = UrbanTryVidlox(query)
    if url <> "" then return url

    ' Try NowStream/NowVideo resolver
    url = UrbanTryNowStream(query)
    if url <> "" then return url

    ' Try OpenLoad/Streamtape resolver
    url = UrbanTryOpenLoad(query)
    if url <> "" then return url

    ' Try RapidVideo resolver
    url = UrbanTryRapidVideo(query)
    if url <> "" then return url

    ' Try StreamCloud resolver
    url = UrbanTryStreamCloud(query)
    if url <> "" then return url

    ' Try UpVid resolver
    url = UrbanTryUpVid(query)
    if url <> "" then return url

    ' Generic search-based fallback
    url = UrbanGenericSearch(query)
    if url <> "" then return url

    ' Try embed URL resolvers (Ok.ru, Vidmoly, Voe, Playmogo). Each provider
    ' gets its own id from the record - the ids are not interchangeable.
    okId = SafeStr(channel, "okId", "")
    vidId = SafeStr(channel, "vidmolyId", "")
    voeId = SafeStr(channel, "voeId", "")
    playId = SafeStr(channel, "playmogoId", "")
    if okId <> "" or vidId <> "" or voeId <> "" or playId <> "" then
        url = UrbanResolveEmbedIds(okId, vidId, voeId, playId)
        if url <> "" then return url
    end if
    ' Legacy single-id field (older callers).
    episodeId = SafeStr(channel, "episodeId", "")
    if episodeId <> "" then
        url = UrbanResolveEmbedUrl(episodeId)
        if url <> "" then return url
    end if

    ' No resolver found
    return ""
end function

' Small string helpers local to this file (no globals elsewhere define
' these names; all function names here use the Urban prefix except the two
' generic guards below, which exist nowhere else in the codebase).
function IsString(v as Dynamic) as Boolean
    t = type(v)
    return t = "String" or t = "roString"
end function

function UrbanReplaceString(s as String, fromStr as String, toStr as String) as String
    if s = invalid or s = "" then return ""
    if fromStr = invalid or fromStr = "" then return s
    if toStr = invalid then toStr = ""
    out = ""
    rest = s
    while true
        p = Instr(1, rest, fromStr)
        if p < 1 then
            out = out + rest
            exit while
        end if
        out = out + Left(rest, p - 1) + toStr
        rest = Mid(rest, p + Len(fromStr))
    end while
    return out
end function

' ---- Vidlox embed resolver ----
function UrbanTryVidlox(query as String) as String
    base = "https://vidlox.tv"
    searchUrl = base + "/search/" + query
    res = HttpGetText(searchUrl, {})
    if not IsString(res.body) then return ""

    ' Look for direct video URL patterns in the response
    patterns = ["file:", "src:", "video_url", "stream_url"]
    for each pat in patterns
        if Instr(1, LCase(res.body), pat) > 0 then
            idx = Instr(1, res.body, pat)
            mid = Mid(res.body, idx + Len(pat))
            q1 = Instr(1, mid, """")
            if q1 > 0 then
                q2 = Instr(q1 + 1, mid, """")
                if q2 > 0 then
                    url = Mid(mid, q1 + 1, q2 - q1 - 1)
                    if url <> "" And InStr(1, url, "http") = 1 then return url
                end if
            end if
        end if
    end for

    ' Also check for embedded JSON with playable URLs
    idx = Instr(1, LCase(res.body), "hdplay")
    if idx > 0 then
        mid = Mid(res.body, idx)
        q1 = Instr(1, mid, """")
        if q1 > 0 then
            q2 = Instr(q1 + 1, mid, """")
            if q2 > 0 then
                url = Mid(mid, q1 + 1, q2 - q1 - 1)
                if url <> "" And InStr(1, url, "http") = 1 then return url
            end if
        end if
    end if

    return ""
end function

' ---- NowStream/NowVideo resolver ----
function UrbanTryNowStream(query as String) as String
    base = "https://nowstream.to"
    searchUrl = base + "/search/" + query
    res = HttpGetText(searchUrl, {})
    if not IsString(res.body) then return ""

    patterns = ["src:", "file:", "hdLink", "playurl"]
    for each pat in patterns
        idx = Instr(1, LCase(res.body), LCase(pat))
        if idx > 0 then
            mid = Mid(res.body, idx + 4)
            q1 = Instr(1, mid, """")
            if q1 > 0 then
                q2 = Instr(q1 + 1, mid, """")
                if q2 > 0 then
                    url = Mid(mid, 1, q2 - q1 - 1)
                    if url <> "" And InStr(1, url, "http") = 1 Then return url
                end if
            end if
        end if
    end for

    ' Check for embedded JSON with direct URLs
    idx = Instr(1, LCase(res.body), "url")
    if idx > 0 then
        mid = Mid(res.body, idx)
        q1 = Instr(1, mid, """")
        if q1 > 0 then
            q2 = Instr(q1 + 1, mid, """")
            if q2 > 0 then
                url = Mid(mid, q1 + 1, q2 - q1 - 1)
                if url <> "" And InStr(1, url, "http") = 1 Then return url
            end if
        end if
    end if

    return ""
end function

' ---- OpenLoad/Streamtape resolver ----
function UrbanTryOpenLoad(query as String) as String
    base = "https://openload.to"
    searchUrl = base + "/search/" + query
    res = HttpGetText(searchUrl, {})
    if not IsString(res.body) then return ""

    patterns = ["openload.to/", "streamtape.com/", "file/"]
    for each pat in patterns
        idx = Instr(1, LCase(res.body), LCase(pat))
        if idx > 0 then
            mid = Mid(res.body, idx)
            q1 = Instr(1, mid, """")
            if q1 > 0 then
                q2 = Instr(q1 + 1, mid, """")
                if q2 > 0 then
                    url = Mid(mid, q1 + 1, q2 - q1 - 1)
                    if url <> "" And InStr(1, url, "http") = 1 Then return url
                end if
            end if
        end if
    end for

    ' Check for JSON with playable URLs
    idx = Instr(1, LCase(res.body), "quality")
    if idx > 0 then
        mid = Mid(res.body, idx)
        q1 = Instr(1, mid, """")
        if q1 > 0 then
            q2 = Instr(q1 + 1, mid, """")
            if q2 > 0 then
                url = Mid(mid, q1 + 1, q2 - q1 - 1)
                if url <> "" And InStr(1, url, "http") = 1 Then return url
            end if
        end if
    end if

    return ""
end function

' ---- RapidVideo resolver ----
function UrbanTryRapidVideo(query as String) as String
    base = "https://rapidvideo.com"
    searchUrl = base + "/search/" + query
    res = HttpGetText(searchUrl, {})
    if not IsString(res.body) then return ""

    patterns = ["rapidvideo.com/", "rvideoplayername", "r video"]
    for each pat in patterns
        idx = Instr(1, LCase(res.body), LCase(pat))
        if idx > 0 then
            mid = Mid(res.body, idx)
            q1 = Instr(1, mid, """")
            if q1 > 0 then
                q2 = Instr(q1 + 1, mid, """")
                if q2 > 0 then
                    url = Mid(mid, q1 + 1, q2 - q1 - 1)
                    if url <> "" And InStr(1, url, "http") = 1 Then return url
                end if
            end if
        end if
    end for

    ' Check for direct video URL patterns
    idx = Instr(1, LCase(res.body), "directlink")
    if idx > 0 then
        mid = Mid(res.body, idx)
        q1 = Instr(1, mid, """")
        if q1 > 0 then
            q2 = Instr(q1 + 1, mid, """")
            if q2 > 0 then
                url = Mid(mid, q1 + 1, q2 - q1 - 1)
                if url <> "" And InStr(1, url, "http") = 1 Then return url
            end if
        end if
    end if

    ' Check for directlink
    idx = Instr(1, LCase(res.body), "directlink")
    if idx > 0 then
        mid = Mid(res.body, idx)
        q1 = Instr(1, mid, """")
        if q1 > 0 then
            q2 = Instr(q1 + 1, mid, """")
            if q2 > 0 then
                url = Mid(mid, q1 + 1, q2 - q1 - 1)
                if url <> "" And InStr(1, url, "http") = 1 Then return url
            end if
        end if
    end if

    return ""
end function

' ---- StreamCloud resolver ----
function UrbanTryStreamCloud(query as String) as String
    base = "https://streamcloud.eu"
    searchUrl = base + "/search/" + query
    res = HttpGetText(searchUrl, {})
    if not IsString(res.body) then return ""

    patterns = ["streamcloud.eu/", "file/", "download/"]
    for each pat in patterns
        idx = Instr(1, LCase(res.body), LCase(pat))
        if idx > 0 then
            mid = Mid(res.body, idx)
            q1 = Instr(1, mid, """")
            if q1 > 0 then
                q2 = Instr(q1 + 1, mid, """")
                if q2 > 0 then
                    url = Mid(mid, q1 + 1, q2 - q1 - 1)
                    if url <> "" And InStr(1, url, "http") = 1 Then return url
                end if
            end if
        end if
    end for

    ' Check for JSON with quality info
    idx = Instr(1, LCase(res.body), "hd")
    if idx > 0 then
        mid = Mid(res.body, idx)
        q1 = Instr(1, mid, """")
        if q1 > 0 then
            q2 = Instr(q1 + 1, mid, """")
            if q2 > 0 then
                url = Mid(mid, q1 + 1, q2 - q1 - 1)
                if url <> "" And InStr(1, url, "http") = 1 Then return url
            end if
        end if
    end if

    return ""
end function

' ---- UpVid resolver ----
function UrbanTryUpVid(query as String) as String
    base = "https://upvid.video"
    searchUrl = base + "/search/" + query
    res = HttpGetText(searchUrl, {})
    if not IsString(res.body) then return ""

    patterns = ["upvid.video/", "file/", "hls/"]
    for each pat in patterns
        idx = Instr(1, LCase(res.body), LCase(pat))
        if idx > 0 then
            mid = Mid(res.body, idx)
            q1 = Instr(1, mid, """")
            if q1 > 0 then
                q2 = Instr(q1 + 1, mid, """")
                if q2 > 0 then
                    url = Mid(mid, q1 + 1, q2 - q1 - 1)
                    if url <> "" And InStr(1, url, "http") = 1 Then return url
                end if
            end if
        end if
    end for

    ' Check for embed page patterns
    idx = Instr(1, LCase(res.body), "embed")
    if idx > 0 then
        mid = Mid(res.body, idx)
        q1 = Instr(1, mid, """")
        if q1 > 0 then
            q2 = Instr(q1 + 1, mid, """")
            if q2 > 0 then
                url = Mid(mid, q1 + 1, q2 - q1 - 1)
                if url <> "" And InStr(1, url, "http") = 1 Then return url
            end if
        end if
    end if

    return ""
end function

' ---- Generic search-based resolver ----
function UrbanGenericSearch(query as String) as String
    ' Best-effort search using multiple free search engines
    ' Tries RapidShare, Uploaded, and similar hosts
    base = "https://rapidshare.com"
    searchUrl = base + "/search/" + query
    res = HttpGetText(searchUrl, {})
    if not IsString(res.body) then return ""

    ' Look for download links
    patterns = ["rapidshare.com/", "dl/", "download/"]
    for each pat in patterns
        idx = Instr(1, LCase(res.body), LCase(pat))
        if idx > 0 then
            mid = Mid(res.body, idx)
            q1 = Instr(1, mid, """")
            if q1 > 0 then
                q2 = Instr(q1 + 1, mid, """")
                if q2 > 0 then
                    url = Mid(mid, q1 + 1, q2 - q1 - 1)
                    if url <> "" And InStr(1, url, "http") = 1 Then return url
                end if
            end if
        end if
    end for

    ' Try Uploaded.to
    base = "https://uploaded.net"
    searchUrl = base + "/search/" + query
    res = HttpGetText(searchUrl, {})
    if not IsString(res.body) then return ""

    patterns = ["uploaded.net/", "dl/", "download/"]
    for each pat in patterns
        idx = Instr(1, LCase(res.body), LCase(pat))
        if idx > 0 then
            mid = Mid(res.body, idx)
            q1 = Instr(1, mid, """")
            if q1 > 0 then
                q2 = Instr(q1 + 1, mid, """")
                if q2 > 0 then
                    url = Mid(mid, q1 + 1, q2 - q1 - 1)
                    if url <> "" And InStr(1, url, "http") = 1 Then return url
                end if
            end if
        end if
    end for

    return ""
end function