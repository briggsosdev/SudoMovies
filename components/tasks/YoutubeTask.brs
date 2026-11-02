' ------------------------------------------------------------------
' YoutubeTask - resolve ONE title's trailer to a YouTube video id and
' (optionally) open it in the Roku YouTube app.
' ------------------------------------------------------------------
'   in : tmdbId, mediaType ("movie"/"tv"), title, tmdbKey, trailerKey, launch
'   out: videoId, errorDetail, status (200 = found [and launched if asked])
'
' WHY THE LOOKUP WAS MISSING TRAILERS: it asked TMDB for
' /videos?language=en-US, and TMDB then only returns videos TAGGED English.
' A large share of titles (new releases, foreign films, anything whose
' trailer is untagged) come back with an empty list for that query even
' though TMDB has a trailer. The lookup now widens in steps:
'   1. en-US + untagged videos
'   2. every common language + untagged
'   3. (tv only) season 1's videos
' and only reports "no trailer" after all of them came back empty.
'
' WHY IT LAUNCHES YOUTUBE: a Roku Video node cannot play a youtube.com watch
' URL (there is no such thing as ContentNode.ifUrlSet), so the old in-app
' TrailerScene always ended in an error. The supported route is a deep link
' into the YouTube channel (id 837) through the device's own ECP port.
' ------------------------------------------------------------------

sub init()
    m.top.functionName = "RunYoutubeTask"
end sub

sub RunYoutubeTask()
    try
        m.top.errorDetail = ""
        m.top.videoId = ""

        vid = ""
        carried = YoutubeInStr("trailerKey", "")
        if carried <> "" then vid = YoutubeKeyOf(carried)

        if vid = "" then
            id = YoutubeInStr("tmdbId", "")
            if id = "" then
                Fail("No title id for a trailer lookup")
                return
            end if
            kind = LCase(YoutubeInStr("mediaType", "movie"))
            if kind <> "tv" then kind = "movie"
            key = YoutubeInStr("tmdbKey", "")
            if key = "" then key = AppConstants().tmdbDefaultKey

            found = YoutubeLookup(kind, id, key)
            if found.vid = "" then
                if found.httpError <> 0 then
                    Fail("Trailer lookup failed (HTTP " + found.httpError.ToStr() + ")")
                else
                    Fail("No trailer published for this title")
                end if
                return
            end if
            vid = found.vid
        end if

        m.top.videoId = vid
        ? "YOUTUBE resolved -> " + vid

        wantLaunch = false
        if m.top.hasField("launch") then
            lv = m.top.getField("launch")
            if lv <> invalid then wantLaunch = (lv = true)
        end if
        if wantLaunch then
            code = YoutubeLaunch(vid)
            if code < 200 or code >= 300 then
                Fail("Couldn't open YouTube (code " + code.ToStr() + "). Set Control by mobile apps to Default.")
                return
            end if
        end if
        m.top.status = 200
    catch e
        ? "YOUTUBE exception: " + YoutubeErrText(e)
        m.top.control = "stop"
        m.top.errorDetail = "Trailer lookup error: " + YoutubeErrText(e)
        m.top.status = 0
    end try
    m.top.control = "stop"
end sub

sub Fail(why as String)
    m.top.errorDetail = why
    m.top.status = 0
    ? "YOUTUBE fail: " + why
    m.top.control = "stop"
end sub

' Returns { vid: String, httpError: Integer }. httpError is the last non-200
' status seen and is only meaningful when vid = "" (so a dead key/network
' reads as an error, while a clean empty answer reads as "no trailer").
function YoutubeLookup(kind as String, id as String, key as String) as Object
    base = AppConstants().tmdbBase + "/" + kind + "/" + YoutubeEncode(id)
    langs = "en,null,es,fr,de,it,pt,ja,ko,hi,zh,ru,tr,pl,nl,sv"
    urls = [
        base + "/videos?language=en-US&include_video_language=en,null",
        base + "/videos?language=en-US&include_video_language=" + langs
    ]
    if kind = "tv" then
        urls.Push(base + "/season/1/videos?language=en-US&include_video_language=" + langs)
    end if
    httpError = 0
    sawOk = false
    for each url in urls
        res = HttpGetText(url, TmdbHeaders(key))
        if res.status = 200 and res.body <> invalid and res.body <> "" then
            sawOk = true
            v = YoutubePickKey(res.body)
            if v <> "" then return { vid: v, httpError: 0 }
        else
            httpError = res.status
            ? "YOUTUBE fetch status=" + res.status.ToStr() + " url=" + url
            ' A rejected key will not get better on retry.
            if res.status = 401 or res.status = 403 then exit for
        end if
    end for
    if sawOk then httpError = 0
    return { vid: "", httpError: httpError }
end function

' Deep-link into the Roku YouTube channel (id 837) via ECP. Tries the
' device's own address first, then loopback. Returns the HTTP code (<= 0 on
' transport failure).
function YoutubeLaunch(vid as String) as Integer
    hosts = []
    try
        di = CreateObject("roDeviceInfo")
        ips = di.GetIPAddrs()
        if ips <> invalid then
            for each k in ips
                ip = ips[k]
                if ip <> invalid and ip <> "" then hosts.Push(ip)
            end for
        end if
    catch e
        ? "YOUTUBE ip lookup failed"
    end try
    hosts.Push("127.0.0.1")
    code = 0
    for each h in hosts
        ut = CreateObject("roUrlTransfer")
        ut.SetUrl("http://" + h + ":8060/launch/837?contentId=" + vid)
        code = ut.PostFromString("")
        ? "YOUTUBE ecp launch host=" + h + " code=" + code.ToStr()
        if code >= 200 and code < 300 then return code
    end for
    return code
end function

' Read one of THIS Task's own interface fields as a string (m.top is an
' roSGNode, so hasField/getField - not DoesExist).
function YoutubeInStr(fieldName as String, fallback as String) as String
    node = m.top
    if node = invalid then return fallback
    if not node.hasField(fieldName) then return fallback
    v = node.getField(fieldName)
    if v = invalid then return fallback
    if type(v) = "roString" or type(v) = "String" then return v
    return v.ToStr()
end function

' Message out of a caught error; never itself able to throw.
function YoutubeErrText(e as Dynamic) as String
    if e = invalid then return "unknown error"
    msg = ""
    t = type(e)
    if t = "roAssociativeArray" or t = "roArray" then
        try
            if e.DoesExist("Message") then
                v = e["Message"]
                if v <> invalid then msg = v.ToStr()
            end if
            if msg = "" and e.DoesExist("Number") then
                v = e["Number"]
                if v <> invalid then msg = "error " + v.ToStr()
            end if
        catch inner
            msg = ""
        end try
    else if t = "String" or t = "roString" then
        msg = e.ToStr()
    else
        try
            msg = e.ToStr()
        catch inner
            msg = "unknown error"
        end try
    end if
    if msg = "" then msg = "unknown error"
    return msg
end function

' ------------------------------------------------------------------
' Pick the best video key out of a TMDB /videos payload. Preference, best
' first:
'   1. YouTube + official + type Trailer
'   2. YouTube + type Trailer
'   3. YouTube + official (teaser etc.)
'   4. any YouTube
' ------------------------------------------------------------------
function YoutubePickKey(body as String) as String
    if body = invalid or body = "" then return ""
    obj = invalid
    try
        obj = ParseJson(body)
    catch e
        return ""
    end try
    if obj = invalid or type(obj) <> "roAssociativeArray" then return ""
    if not obj.DoesExist("results") then return ""
    results = obj["results"]
    if results = invalid or type(results) <> "roArray" then return ""

    fallback = ""
    officialAny = ""
    for each r in results
        if r <> invalid and type(r) = "roAssociativeArray" then
            k = YoutubeKeyOf(SafeStr(r, "key", ""))
            if k <> "" then
                if LCase(SafeStr(r, "site", "")) = "youtube" then
                    isTrailer = (InStr(1, LCase(SafeStr(r, "type", "")), "trailer") > 0)
                    isOfficial = YoutubeIsOfficial(r)
                    if isTrailer and isOfficial then
                        return k
                    else if isTrailer then
                        if fallback = "" then fallback = k
                    else if isOfficial then
                        if officialAny = "" then officialAny = k
                    else if fallback = "" then
                        fallback = k
                    end if
                end if
            end if
        end if
    end for
    if officialAny <> "" then return officialAny
    return fallback
end function

' TMDB sends "official" as a JSON boolean.
function YoutubeIsOfficial(r as Object) as Boolean
    if r = invalid or type(r) <> "roAssociativeArray" then return false
    if not r.DoesExist("official") then return false
    v = r["official"]
    if v = invalid then return false
    if type(v) = "Boolean" or type(v) = "roBoolean" then
        return (v = true)
    end if
    return (LCase(v.ToStr().Trim()) = "true")
end function

' TMDB keys are 11-char YouTube ids; anything else is treated as absent.
function YoutubeKeyOf(k as String) as String
    if k = invalid then return ""
    k = k.Trim()
    if k.Len() <> 11 then return ""
    for i = 1 to k.Len()
        c = Mid(k, i, 1)
        if InStr(1, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-", c) = 0 then
            return ""
        end if
    end for
    return k
end function

' Percent-encodes one byte as %XX (uppercase hex) without Hex().
function ByteToHex(b as Integer) as String
    digits = "0123456789ABCDEF"
    v = b
    if v < 0 then v = 0
    if v > 255 then v = 255
    hi = Int(v / 16)
    lo = v - (hi * 16)
    return Mid(digits, hi + 1, 1) + Mid(digits, lo + 1, 1)
end function

function YoutubeEncode(s as String) as String
    if s = invalid then return ""
    s = s.Trim()
    out = ""
    for i = 1 to s.Len()
        c = Mid(s, i, 1)
        if InStr(1, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.~", c) > 0 then
            out = out + c
        else
            out = out + "%" + ByteToHex(Asc(c))
        end if
    end for
    return out
end function
