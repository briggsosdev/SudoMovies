' UrbanTask: multi-provider stream resolver for the Urban catalog.
'
' Runs on the task thread (roUrlTransfer lives in Http.brs / UrbanStreams.brs
' and is illegal on the render thread). Same candidates/status/errorDetail
' contract as FemboxTask/VixSrcTask so HomeScene can chain it and merge the
' results into one source picker.
'
' ORDER MATTERS - measured, not guessed:
'   1. Verified embed resolvers (OK.ru, Vidmoly). These were live-verified
'      end to end: embed page HTTP 200 -> manifest HTTP 200 -> #EXTM3U.
'      Each provider gets ITS OWN id (okId / vidmolyId / ...), because ids
'      are not interchangeable across sites.
'   2. Title-search providers. ALL of these were re-tested live and are dead:
'      streamcloud.to is a parked "domain for sale" page, upvid.to returns
'      nothing, vidlox.tv answers with a
'      JavaScript "Redirecting..." shell that has no video links to scrape.
'      The old chain still walked all eight on every episode, which cost up
'      to 8 x 15s of timeouts to reach the same empty result. They are now
'      gated behind tryLegacySearch (default false) so they cost nothing but
'      stay in the codebase for a re-test instead of being deleted.
sub init()
    m.top.functionName = "RunUrban"
end sub

' Flip to true to re-enable the legacy title-search chain.
function UrbanLegacySearchEnabled() as Boolean
    return false
end function

sub RunUrban()
    ' try/catch guarantees a terminal status + control="stop" on every exit
    ' path (an uncaught error would strand the caller's progress overlay).
    try
        m.top.candidates = []
        title = m.top.title
        if title = invalid then title = ""
        mType = m.top.mediaType
        if mType = invalid then mType = ""
        s = m.top.season
        if s = invalid or s = "" then s = "1"
        e = m.top.episode
        if e = invalid or e = "" then e = "1"

        found = []

        ' ---- 1. Verified embed providers, each with its own id ----
        okId = UrbanTopStr("okId")
        vidId = UrbanTopStr("vidmolyId")
        voeId = UrbanTopStr("voeId")
        playId = UrbanTopStr("playmogoId")

        if okId <> "" then
            UrbanCollectTry(found, "OKRU", UrbanTryOkRuUrl(okId))
        end if
        if vidId <> "" then
            UrbanCollectTry(found, "VIDMOLY", UrbanTryVidmolyUrl(vidId))
        end if
        if voeId <> "" then
            UrbanCollectTry(found, "VOE", UrbanTryVoeUrl(voeId))
        end if
        if playId <> "" then
            UrbanCollectTry(found, "PLAYMOGO", UrbanTryPlaymogoUrl(playId))
        end if

        ' ---- 2. Optional legacy title-search chain (all providers dead) ----
        if found.count() = 0 and UrbanLegacySearchEnabled() then
            epTitle = ""
            if mType = "tv" then epTitle = "S" + s + "E" + e
            query = LCase(title + " " + epTitle)
            query = UrbanReplaceString(query, " ", "+")
            query = UrbanReplaceString(query, "'", "%27")
            UrbanCollectTry(found, "VIDLOX", UrbanTryVidlox(query))
            UrbanCollectTry(found, "NOWSTREAM", UrbanTryNowStream(query))
            UrbanCollectTry(found, "OPENLOAD", UrbanTryOpenLoad(query))
            UrbanCollectTry(found, "RAPIDVIDEO", UrbanTryRapidVideo(query))
            UrbanCollectTry(found, "STREAMCLOUD", UrbanTryStreamCloud(query))
            UrbanCollectTry(found, "UPVID", UrbanTryUpVid(query))
            UrbanCollectTry(found, "WEB", UrbanGenericSearch(query))
        end if

        if found.count() = 0 then
            if okId = "" and vidId = "" then
                m.top.errorDetail = "No Urban provider ids for this title."
            else
                m.top.errorDetail = "OK.ru and Vidmoly had no playable stream for this episode."
            end if
            m.top.status = 204
            m.top.control = "stop"
            return
        end if

        m.top.candidates = found
        m.top.status = 200
    catch e
        m.top.errorDetail = "Urban task error: " + TaskErrorText(e)
        m.top.status = 204
    end try
    m.top.control = "stop"
end sub

' Read a string interface field off the task node without throwing when the
' field was never assigned (an unset string field reads back as invalid).
function UrbanTopStr(key as String) as String
    v = m.top[key]
    if v = invalid then return ""
    if type(v) = "String" or type(v) = "roString" then return v.ToStr()
    return ""
end function

' Append one provider candidate when the resolver produced a URL. Label
' carries the provider tag + container so the picker reads like the
' FEM/VIX entries; format "hls" lets PlaybackScene set streamFormat.
' Referer is passed through as httpHeaders - OK.ru and Vidmoly both serve
' 403 to a Roku client that omits it, and PlaybackScene honours the field.
sub UrbanCollectTry(found as Object, tag as String, url as String)
    if url = invalid or url = "" then return
    if Left(url, 4) <> "http" then return
    fmt = "mp4"
    suffix = "MP4"
    if Instr(1, LCase(url), ".m3u8") > 0 then
        fmt = "hls"
        suffix = "HLS"
    end if
    hdrs = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"
    }
    if tag = "OKRU" then
        hdrs["Referer"] = "https://ok.ru/"
    else if tag = "VIDMOLY" then
        hdrs["Referer"] = "https://vidmoly.org/"
    end if
    found.Push({
        url: url,
        quality: "",
        label: tag + " " + suffix,
        headers: hdrs,
        subtitles: [],
        format: fmt,
        score: 0
    })
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