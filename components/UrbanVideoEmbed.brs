' UrbanVideoEmbed.brs — embed resolvers with LIVE-VERIFIED extraction patterns.
' Patterns confirmed against real HTTP responses (#EXTM3U validated):
'   OK.ru:    embed page -> data-options attr -> entity decode -> JSON -> hlsManifestUrl
'   Vidmoly:  embed page -> jwplayer sources file key -> master.m3u8 (with ?t= token)
'   Voe:      JS redirect only (serves placeholder MP4, no HLS) - low priority
'   Playmogo: 403 Forbidden - blocked, skip entirely

function UrbanTryOkRuUrl(episodeId as String) as String
    base = "https://ok.ru/videoembed/" + episodeId
    res = HttpGetText(base, { "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36" })
    if not IsString(res.body) then return ""

    ? "OK.RU: HTTP " + res.status.ToStr() + " body_len=" + res.body.len()

    ' CONFIRMED: data-options attribute holds player JSON with hlsManifestUrl
    hls = OkRuExtractHls(res.body)
    if hls = "" then
        ? "OK.RU: no hlsManifestUrl found"
        return ""
    end if

    ' NO pre-flight GET here: the OK.ru signature is single-use and a probe
    ' burns it. See the note above UrbanResolveEmbedIds.
    ? "OK.RU: hls=" + hls + " (unvalidated, single-use token)"
    return hls
end function

function UrbanTryVidmolyUrl(episodeId as String) as String
    base = "https://vidmoly.org/embed-" + episodeId + ".html"
    res = HttpGetText(base, { "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36" })
    if not IsString(res.body) then return ""

    ? "Vidmoly: HTTP " + res.status.ToStr() + " body_len=" + res.body.len()

    ' CONFIRMED: jwplayer sources file key carries the master.m3u8 URL with token
    hls = VidmolyExtractHls(res.body)
    if hls = "" then
        ? "Vidmoly: no master.m3u8 found"
        return ""
    end if

    ' Same single-use hazard as OK.ru (the ?t= token is minted per embed
    ' fetch): no pre-flight GET. See the note above UrbanResolveEmbedIds.
    ? "Vidmoly: hls=" + hls + " (unvalidated, single-use token)"
    return hls
end function

function UrbanTryVoeUrl(episodeId as String) as String
    ' LIVE-TESTED: voe.sx serves a JS redirect page to a mirror host. The
    ' mirror exposes a "file" key, but the SAMPLE id resolved to
    ' test-videos.co.uk (Big Buck Bunny) - i.e. a demo clip, not the episode.
    ' Returning that would hand the user a silent fake, so known placeholder
    ' hosts are now rejected outright.
    base = "https://voe.sx/e/" + episodeId
    res = HttpGetText(base, { "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" })
    if not IsString(res.body) then return ""

    ? "Voe: HTTP " + res.status.ToStr() + " body_len=" + res.body.len()

    ' Extract window.location.href redirect target
    marker = "window.location.href = '"
    p = Instr(1, res.body, marker)
    if p = 0 then return ""
    start = p + Len(marker)
    fin = Instr(start, res.body, "'")
    if fin = 0 then return ""
    target = Mid(res.body, start, fin - start)
    if target = "" or Left(target, 4) <> "http" then return ""

    ? "Voe: redirect=" + target
    ' Fetch the redirect target and look for any direct file URL
    r2 = HttpGetText(target, { "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36", "Referer": base })
    if not IsString(r2.body) then return ""
    fileUrl = UrbanExtractJsonString(r2.body, "file")
    if fileUrl = "" then fileUrl = UrbanExtractJsonString(r2.body, "source")
    if fileUrl = "" or Left(fileUrl, 4) <> "http" then return ""
    if UrbanIsPlaceholderMedia(fileUrl) then
        ? "Voe: rejecting demo clip (not the real episode): " + fileUrl
        return ""
    end if
    ? "Voe: file=" + fileUrl
    return fileUrl
end function

' True when a URL points at a public sample/test clip rather than the actual
' episode. Offering one of these is worse than offering nothing: playback
' starts, looks fine, and shows the wrong programme with no way to tell.
function UrbanIsPlaceholderMedia(url as String) as Boolean
    if url = invalid or url = "" then return true
    u = LCase(url)
    for each host in [
        "test-videos.co.uk",
        "commondatastorage.googleapis.com/gtv-videos-bucket",
        "download.blender.org",
        "sample-videos.com",
        "www.w3schools.com/html/mov_bbb.mp4",
        "joy1.videvo.net",
        "media.w3.org"
    ]
        if Instr(1, u, host) > 0 then
            return true
        end if
    end for
    ' Demo filenames even on an unknown host.
    if Instr(1, u, "bigbuckbunny") > 0 then return true
    if Instr(1, u, "sample") > 0 and Instr(1, u, ".mp4") > 0 then return true
    return false
end function

function UrbanTryPlaymogoUrl(episodeId as String) as String
    ' LIVE-TESTED: playmogo.com returns 403 Forbidden without cookies.
    ' No workable resolver without a browser session. Skip.
    ? "Playmogo: skipped (403 Forbidden on all tested requests)"
    return ""
end function

' NOTE ON URL VALIDATION (live-verified 2026-10-03)
'
' OK.ru signs its HLS master URL and the token is STRICTLY SINGLE-USE:
'   attempt 1 (same URL) : HTTP 200, #EXTM3U present
'   attempt 2 (same URL) : HTTP 400
'   attempt 3 (same URL) : HTTP 400
'   fresh embed fetch    : HTTP 200 again (new signature minted)
'
' So a pre-flight "is this URL valid?" GET DESTROYS the only copy of the
' token, and PlaybackScene then plays a URL that already 400s. That is why
' every episode resolved a URL and still played blank: the resolver consumed
' the token, not the network. Validation was removed rather than "fixed" -
' there is no non-consuming way to probe a single-use URL.
'
' The structural guard (Lef(t, 4) = "http") plus OkRuExtractHls already
' reject malformed output, and a bad URL now surfaces honestly as a playback
' error instead of being silently discarded here.

' Main resolver, provider-aware. Every argument is that provider's OWN id:
' the same episode has four different ids across these sites, so the old
' single-episodeId signature could only ever work for whichever site the id
' happened to come from (OK.ru first, so Vidmoly/Voe/Playmogo were never
' really exercised). Returns the first URL that resolves.
function UrbanResolveEmbedIds(okId as String, vidmolyId as String, voeId as String, playmogoId as String) as String
    if okId <> invalid and okId <> "" then
        url = UrbanTryOkRuUrl(okId)
        if url <> "" then return url
    end if
    if vidmolyId <> invalid and vidmolyId <> "" then
        url = UrbanTryVidmolyUrl(vidmolyId)
        if url <> "" then return url
    end if
    if voeId <> invalid and voeId <> "" then
        url = UrbanTryVoeUrl(voeId)
        if url <> "" then return url
    end if
    if playmogoId <> invalid and playmogoId <> "" then
        url = UrbanTryPlaymogoUrl(playmogoId)
        if url <> "" then return url
    end if
    return ""
end function

' Legacy single-id entry point, kept for callers that only have one id.
' Tries it as an OK.ru id first, then as a Vidmoly id.
function UrbanResolveEmbedUrl(episodeId as String) as String
    if episodeId = invalid or episodeId = "" then return ""
    return UrbanResolveEmbedIds(episodeId, episodeId, "", "")
end function

' Full candidate version - returns {url, quality, label, type, headers, score}
function UrbanResolveEmbedFull(episodeId as String, outCand as Object) as Boolean
    url = UrbanResolveEmbedUrl(episodeId)
    if url = "" then return false
    outCand.url = url
    outCand.quality = ""
    if Instr(1, LCase(url), ".m3u8") > 0 then
        outCand.type = "hls"
        outCand.label = "EMBED HLS"
    else
        outCand.type = "file"
        outCand.label = "EMBED MP4"
    end if
    outCand.headers = { "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36" }
    outCand.score = 0
    return true
end function

' ===========================================================================
' CONFIRMED OK.ru EXTRACTION
' data-options attr -> entity decode -> find hlsManifestUrl in player JSON
' ===========================================================================

function OkRuExtractHls(body as String) as String
    if body = "" then return ""
    marker = "data-options=" + Chr(34)
    p = Instr(1, body, marker)
    if p = 0 then return ""
    start = p + Len(marker)
    fin = Instr(start, body, Chr(34))
    if fin = 0 then return ""
    raw = Mid(body, start, fin - start)
    json = UrbanEntityDecode(raw)
    hls = UrbanExtractJsonString(json, "hlsManifestUrl")
    if hls <> "" then return hls
    ' Fallback: first entry of videos array (progressive mp4 urls)
    vp = Instr(1, json, Chr(34) + "videos" + Chr(34))
    if vp = 0 then return ""
    up = Instr(vp, json, Chr(34) + "url" + Chr(34) + ":")
    if up = 0 then return ""
    q1 = Instr(up + Len(Chr(34) + "url" + Chr(34) + ":"), json, Chr(34))
    if q1 = 0 then return ""
    q2 = Instr(q1 + 1, json, Chr(34))
    if q2 = 0 then return ""
    return Mid(json, q1 + 1, q2 - q1 - 1)
end function

' ===========================================================================
' CONFIRMED VIDMOLY EXTRACTION
' master.m3u8 walk-back to quote start, then forward to quote end
' (captures the ?t= token query). URL may contain commas - only stop at
' quote chars, whitespace, and newlines.
' ===========================================================================

function VidmolyExtractHls(body as String) as String
    if body = "" then return ""
    key = "master.m3u8"
    p = Instr(1, body, key)
    if p = 0 then return ""
    start = p
    while start > 1
        ch = Mid(body, start - 1, 1)
        if ch = Chr(34) or ch = "'" or ch = Chr(10) or ch = Chr(13) then
            exit while
        end if
        start = start - 1
    end while
    url = Mid(body, start, p + Len(key) - start)
    ' Forward past .m3u8 to capture the token query until closing quote
    fin = p + Len(key)
    n = Len(body)
    while fin < n
        ch = Mid(body, fin + 1, 1)
        if ch = Chr(34) or ch = "'" or ch = Chr(10) or ch = Chr(13) or ch = Chr(32) then
            exit while
        end if
        fin = fin + 1
    end while
    if fin > p + Len(key) - 1 then
        url = url + Mid(body, p + Len(key), fin - (p + Len(key)) + 1)
    end if
    if Left(url, 2) = "//" then
        url = "https:" + url
    end if
    if Left(url, 4) <> "http" then return ""
    return url
end function

' HTML entity decoder for the data-options attr
function UrbanEntityDecode(s as String) as String
    out = s
    amp = Chr(38)
    out = out.Replace(amp + "quot;", Chr(34))
    out = out.Replace(amp + "#34;", Chr(34))
    out = out.Replace(amp + "#39;", "'")
    out = out.Replace(amp + "apos;", "'")
    out = out.Replace(amp + "amp;", amp)
    out = out.Replace("\u0026", amp)
    out = out.Replace("\/", "/")
    return out
end function

' Extract a JSON string value by key
function UrbanExtractJsonString(body as String, key as String) as String
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

' Retained for callers that hold a NON-token URL (a plain CDN playlist).
' MUST NOT be used on an OK.ru/Vidmoly master URL: fetching it consumes the
' single-use signature and the subsequent playback 400s. Structural-only
' check that does not touch the network.
function UrbanValidateHlsUrl(masterUrl as String, refH as Object) as Boolean
    if masterUrl = invalid or masterUrl = "" then return false
    if Left(masterUrl, 4) <> "http" then return false
    if Instr(1, LCase(masterUrl), ".m3u8") = 0 then return false
    return true
end function