' VixSrc resolver (vixsrc.to): TMDB id -> HLS master playlist.
' 1. GET https://vixsrc.to/api/movie/{id} (or /api/tv/{id}/{s}/{e})
'    -> JSON { "src": "/embed/...?token=..&expires=.." }
' 2. GET https://vixsrc.to{src} with Referer -> static HTML containing
'    window.masterPlaylist = { params: { 'token','expires' }, url: '.../playlist/..' }
' 3. Master URL = url + "?token=..&expires=..&h=1", validated, handed to Video as HLS.
' No key, no JS, no DRM. Plain roUrlTransfer GETs only.
sub init()
    m.top.functionName = "RunVixSrc"
end sub

function VixExtractJsonString(body as String, key as String) as String
    if body = invalid or body = "" then return ""
    if key = invalid or key = "" then return ""
    pat = Chr(34) + key + Chr(34)
    i = Instr(1, body, pat)
    if i = 0 then return ""
    j = Instr(i + Len(pat), body, ":")
    if j = 0 then return ""
    k = Instr(j + 1, body, Chr(34))
    if k = 0 then return ""
    m2 = Instr(k + 1, body, Chr(34))
    if m2 = 0 then return ""
    return Mid(body, k + 1, m2 - k - 1)
end function

function VixExtractJsValue(chunk as String, key as String) as String
    if chunk = invalid or chunk = "" then return ""
    if key = invalid or key = "" then return ""
    i = Instr(1, chunk, key)
    if i = 0 then return ""
    j = Instr(i + Len(key), chunk, ":")
    if j = 0 then return ""
    p = j + 1
    n = Len(chunk)
    while p <= n and (Mid(chunk, p, 1) = " " or Mid(chunk, p, 1) = Chr(9))
        p = p + 1
    end while
    if p > n then return ""
    q = Mid(chunk, p, 1)
    if q = "'" or q = Chr(34) then
        m2 = Instr(p + 1, chunk, q)
        if m2 = 0 then return ""
        return Mid(chunk, p + 1, m2 - p - 1)
    end if
    ' Unquoted value (number): read until delimiter.
    m2 = p
    while m2 <= n
        ch = Mid(chunk, m2, 1)
        if ch = "," or ch = "}" or ch = " " or ch = Chr(9) or ch = Chr(10) or ch = Chr(13) then
            exit while
        end if
        m2 = m2 + 1
    end while
    return Mid(chunk, p, m2 - p)
end function

sub RunVixSrc()
    ' Any uncaught error here would leave the task at control="run" with no
    ' status event, so the caller's observer never fires and the progress
    ' overlay stays up forever (stuck Watch-now). try/catch guarantees a
    ' terminal status + control="stop" on every exit path.
    try
    m.top.candidates = []
    tmdbId = m.top.tmdbId
    if tmdbId = invalid then tmdbId = ""
    mType = m.top.mediaType
    if mType = invalid then mType = ""
    s = m.top.season
    if s = invalid or s = "" then s = "1"
    e = m.top.episode
    if e = invalid or e = "" then e = "1"
    if tmdbId = "" then
        m.top.errorDetail = "No TMDB id."
        m.top.status = 400
        m.top.control = "stop"
        return
    end if

    ua = { "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36" }
    if mType = "tv" then
        apiUrl = "https://vixsrc.to/api/tv/" + tmdbId + "/" + s + "/" + e
    else
        apiUrl = "https://vixsrc.to/api/movie/" + tmdbId
    end if
    res = HttpGetText(apiUrl, ua)
    if res.status <> 200 then
        m.top.errorDetail = "VixSrc API failed (HTTP " + res.status.ToStr() + ")."
        m.top.status = res.status
        m.top.control = "stop"
        return
    end if

    src = VixExtractJsonString(res.body, "src")
    if src = "" then
        m.top.errorDetail = "VixSrc returned no embed."
        m.top.status = 204
        m.top.control = "stop"
        return
    end if
    ' API escapes slashes as \/ — unescape before use.
    src = src.Replace("\/", "/")
    if Left(src, 1) = "/" then src = "https://vixsrc.to" + src

    refH = { "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36", "Referer": "https://vixsrc.to/" }
    page = HttpGetText(src, refH)
    if page.status <> 200 then
        m.top.errorDetail = "VixSrc embed failed (HTTP " + page.status.ToStr() + ")."
        m.top.status = page.status
        m.top.control = "stop"
        return
    end if

    html = page.body
    mp = Instr(1, html, "window.masterPlaylist")
    chunk = ""
    if mp > 0 then
        chunk = Mid(html, mp, 2000)
    else
        chunk = html
    end if
    tok = VixExtractJsValue(chunk, "'token'")
    exp = VixExtractJsValue(chunk, "'expires'")
    purl = VixExtractJsValue(chunk, "url")
    if tok = "" or purl = "" then
        ' Fallback: window.streams entries carry "url":"https://vixsrc.to/playlist/.."
        purl = VixExtractJsonString(chunk, "url")
        if purl = "" then
            purl = VixExtractJsonString(html, "url")
        end if
    end if
    if purl = "" then
        m.top.errorDetail = "VixSrc returned no playlist."
        m.top.status = 204
        m.top.control = "stop"
        return
    end if

    master = purl
    if tok <> "" then
        sep = "?"
        if Instr(1, master, "?") > 0 then sep = "&"
        master = master + sep + "token=" + tok
        if exp <> "" then
            master = master + "&expires=" + exp
        end if
        master = master + "&h=1"
    end if

    chk = HttpGetText(master, refH)
    if chk.status <> 200 or Instr(1, chk.body, "#EXTM3U") = 0 then
        m.top.errorDetail = "VixSrc playlist invalid."
        m.top.status = 204
        m.top.control = "stop"
        return
    end if

    cand = {
        url: master,
        quality: "1080p",
        label: "VIX 1080p HLS",
        headers: { Referer: "https://vixsrc.to/" },
        subtitles: [],
        format: "hls",
        score: 0
    }
    arr = []
    arr.Push(cand)
    m.top.candidates = arr
    m.top.status = 200
    catch e
        ' Defensive message extraction (audit finding): a throw inside the
        ' catch would skip the terminal status write and strand the resolve.
        m.top.errorDetail = "VixSrc task error: " + TaskErrorText(e)
        m.top.status = 204
    end try
    m.top.control = "stop"
end sub

' e.Message may be missing/invalid on this firmware; never let the catch
' itself throw (pattern from LiveTvTaskErrorText).
function TaskErrorText(e as Dynamic) as String
    if e <> invalid and type(e) = "roAssociativeArray" and e.DoesExist("Message") then
        msg = e["Message"]
        if msg <> invalid and (type(msg) = "String" or type(msg) = "roString") and msg <> "" then
            return msg
        end if
    end if
    return "unexpected error"
end function