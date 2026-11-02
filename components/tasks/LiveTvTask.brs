' LiveTvTask.brs — Task-thread fetch + cache for the free USA FAST lineup.
'
' FETCH PLAN (verified 2026-09-19 from a plain HTTPS client; no device used):
'   LINEUP: primary is the plain JSON index (.channels.json, HTTP 200,
'   application/json, ~1.9MB, 582 US channels with real chno) parsed by
'   LiveTvParseChannels(). Fallback (used only when the primary yields no
'   usable channels — it 404'd in a previous round) is the plain XMLTV feed
'   us.xml parsed by LiveTvParseChannelsFromXmltv(). GUIDE: always the plain
'   XMLTV feed us.xml (~3.0MB, text/plain, HTTP 200) parsed by
'   LiveTvParseEpg(). When the lineup came from XMLTV, the same download is
'   reused for the guide (m.liveTvXmlBody); when it came from JSON the body
'   is NOT reused (it has no <programme> blocks) and the guide fetches
'   us.xml itself. Worst realistic run: JSON lineup (<=20s) + guide primary
'   + fallback (<=35s) <= 55s, inside the scene's 85s load watchdog
'   (loadTimer in LiveTvScene.xml); if both lineup fetches time out the
'   task exits early with status 11 and never starts the guide fetch.
'   Retired 2026-09-19: both .gz URLs (.channels.json.gz ~542KB, us.xml.gz
'   ~507KB) — application/octet-stream with NO Content-Encoding, so
'   EnableEncodings cannot inflate them and BrightScript has no gunzip
'   primitive. Fetching them wasted the watchdog budget and exposed
'   Len/Instr/ParseJson to binary bodies, which is the pre-2026-09-19
'   error-99 path (exception on a non-string body, caught below as 99).
'
' BODY SAFETY: LiveTvFetchText() coerces every body to a String (never
'   invalid), and every Len/Instr/parse touch goes through LiveTvBodyUsable()
'   first, so a hostile or binary payload can only produce status 11/12/21/22
'   with an explanatory errorDetail, never an exception.
'   TRIM NOTE (2026-09-19): Trim() does NOT exist as a global BrightScript
'   function (verified against the current Roku docs: global string functions
'   + global utility functions list no Trim; the BrighterScript compiler's
'   known globals have none either). ifStringOps.Trim() (s.Trim()) is the
'   only form. Every bare Trim() call in LiveTvTask.brs + LiveTv.brs threw at
'   runtime — the one in RunLiveTv setup (LCase(Trim(taskMode))) fired BEFORE
'   any print and was caught as the old status 99: the zero-prints mystery.
'   The same trap was still live in YoutubeTask.brs until 2026-09-26, in three
'   places every single trailer lookup passes through (YoutubeIsOfficial,
'   YoutubeKeyOf, YoutubeEncode), which is why trailers reported one generic
'   "Trailer lookup error" for every title. The `.Trim()` METHOD form is the
'   only safe spelling.
'
' CACHING (never the registry: 32KB total): tmp:/livetv_channels.json,
'   tmp:/livetv_epg.json, tmp:/livetv_meta.json ({ channelsAt, epgAt } epoch).
'   Fresh cache (< LiveTvCacheTtlSec, daily poll) is served with fromCache=true
'   and no network. tmp:/ can vanish on reboot, missing files refetch.
'   forceRefresh=true bypasses the cache for a manual refresh.
'
' STATUS: 200 = ok (fresh or cached). 11 = lineup fetch failed. 12 = lineup
'   unparseable (gzipped bytes / no usable channels). 21 = epg fetch failed.
'   22 = epg unparseable. 98 = unexpected exception (the catch below; retired
'   the old 99 code so the previous mystery status can never recur), and its
'   errorDetail always names the run stage ("setup"/"cache-serve"/
'   "channels-fetch"/"epg-fetch") plus the exception message. errorDetail is
'   written BEFORE the terminal status write: the status write wakes the
'   alwaysNotify observer while the task thread is still parked, so a detail
'   set after status was read as "" (the screen showed the generic "code 99"
'   instead of the real message). Every exit path ends with control="stop".
'   NOTE: status is never reset at the top (see FemboxTask.brs): with
'   alwaysNotify="true", writing the initial 0 would fire observers early.

sub init()
    m.top.functionName = "RunLiveTv"
end sub

sub RunLiveTv()
    ' Observability: prints are the only console visibility on this firmware.
    ' Entry + progress prints below make the next debug round show exactly how
    ' far the run got (the old status-99 bug threw BEFORE the first print).
    ' m.liveTvStage is an m-level marker (not an interface field: no observer
    ' fires on it) that the catch includes in errorDetail.
    m.liveTvStage = "setup"
    ? "LIVETV task entered"
    try
        taskMode = m.top.mode
        if taskMode = invalid or taskMode = "" then
            taskMode = "all"
        end if
        ' Trim() does NOT exist as a global function (verified against the Roku
        ' docs: global string functions + global utility functions list no
        ' Trim; ifStringOps.Trim() is the only form). The bare Trim() call here
        ' threw at runtime before any print - the root cause of status 99.
        taskMode = LCase(taskMode.Trim())
        wantChannels = taskMode = "all" or taskMode = "channels"
        wantEpg = taskMode = "all" or taskMode = "epg"

        chanUrl = m.top.channelsUrl
        if chanUrl = invalid or chanUrl = "" then
            chanUrl = LiveTvChannelsUrl()
        end if
        guideUrl = m.top.epgUrl
        if guideUrl = invalid or guideUrl = "" then
            guideUrl = LiveTvEpgUrl()
        end if
        capCount = m.top.maxChannels
        if capCount = invalid or capCount <= 0 then
            capCount = LiveTvMaxChannels()
        end if
        pivot = m.top.nowSec
        if pivot = invalid or pivot <= 0 then
            pivot = LiveTvNowSec()
        end if
        ? "LIVETV task setup done mode=" + taskMode + " channels=" + wantChannels.ToStr() + " epg=" + wantEpg.ToStr() + " cap=" + capCount.ToStr() + " pivot=" + pivot.ToStr()

        ' Premium per-tune stream resolution (cinevid): one fresh
        ' /api/stream/{id} call; tokens are short-lived so every tune
        ' resolves anew (never cached). Own fetch/parse/status path,
        ' never touches the lineup/EPG machinery below.
        if taskMode = "resolve" then
            m.liveTvStage = "resolve"
            RunCineVidResolve()
            m.top.control = "stop"
            return
        end if

        ' Sudo Movies per-movie stream resolution (VixSrc pattern, task thread
        ' only): resolveId carries the TMDB id; resolvedUrl + resolveStatus out
        ' (200 ok / 11 failed). Own path, never touches lineup/EPG machinery.
        if taskMode = "sudoresolve" then
            m.liveTvStage = "sudoresolve"
            RunSudoResolve()
            m.top.control = "stop"
            return
        end if

        ' Streaming TV Guides fallback (streamingtvguides.com): supplementary
        ' guide source when the mjh.nz XMLTV guide fails. Parses the
        ' server-rendered Samsung TV Plus guide pages into the same
        ' {epgId: {programs, now, next}} shape; keys are NORMALIZED channel
        ' names (the scene falls back to name-based lookup). Own fetch/parse,
        ' never touches the lineup machinery below.
        if taskMode = "stvg" then
            m.liveTvStage = "stvg"
            RunStvgGuide()
            m.top.control = "stop"
            return
        end if

        ' Premium lineup (cinevid): channels only (no XMLTV guide exists
        ' for these), own tmp:/ cache files. Never reaches the free FAST
        ' fetch/cache paths below.
        source = m.top.source
        if source = invalid then
            source = ""
        end if
        isPremium = (LCase(source.Trim()) = "premium")
        if isPremium then
            RunCineVidLineup(wantChannels, pivot)
            m.top.control = "stop"
            return
        end if

        ' Sudo Movies virtual-channel lineup: TMDB trending feed + fabricated
        ' guide slots. Own cache file, never reaches the free FAST paths below.
        if taskMode = "sudo" then
            m.liveTvStage = "sudo-lineup"
            RunSudoLineup()
            m.top.control = "stop"
            return
        end if

        m.top.fromCache = false
        m.liveTvXmlBody = ""

        if not m.top.forceRefresh then
            m.liveTvStage = "cache-serve"
            ? "LIVETV cache check entered"
            served = LiveTvServeCache(wantChannels, wantEpg, pivot)
            ? "LIVETV cache check exit served=" + served.ToStr()
            if served then
                m.top.control = "stop"
                return
            end if
        end if

        m.liveTvStage = "channels-fetch"
        channels = []
        if wantChannels then
            channels = LiveTvLoadChannels(chanUrl, capCount)
            if channels = invalid then
                m.top.control = "stop"
                return
            end if
            m.top.channels = channels
        else
            cached = LiveTvCacheReadJson("livetv_channels.json")
            if cached <> invalid and type(cached) = "roArray" then
                channels = cached
            end if
        end if

        ' Seed now/next from the per-channel `programs` arrays the lineup
        ' already carries, so the grid never opens on genre-only labels while
        ' (or instead of) the 2.9MB XMLTV scan. The epg-fetch stage below
        ' OVERWRITES this with the richer <desc>-bearing map when it completes;
        ' on its failure paths it returns before m.top.epg is touched, so this
        ' seed survives and the partial-success route in the scene keeps it.
        if channels.count() > 0 then
            seedEpg = LiveTvLineupEpg(channels, pivot)
            if seedEpg.count() > 0 then
                m.top.epg = seedEpg
                ? "LIVETV epg seeded from lineup channels=" + seedEpg.count().ToStr()
            end if
        end if

        m.liveTvStage = "epg-fetch"
        if wantEpg then
            wanted = invalid
            if channels.count() > 0 then
                wanted = LiveTvWantedIds(channels)
            end if
            epg = LiveTvLoadEpg(guideUrl, wanted, pivot)
            if epg = invalid then
                m.top.control = "stop"
                return
            end if
            m.top.epg = epg
        end if

        if m.top.status = 0 then
            m.top.status = 200
        end if
    catch e
        ' Payload BEFORE the terminal status write: the status write wakes the
        ' alwaysNotify observer on the render thread while this task thread is
        ' still parked here, so errorDetail set AFTER status was read as ""
        ' (the screen then showed the generic "code 99" instead of the real
        ' message). errorDetail first, status last - matches FemboxTask.brs.
        ' Status 98 (never 99) so a future unexpected exception can never
        ' masquerade as the old mystery code; the stage marker names exactly
        ' how far the run got.
        stage = m.liveTvStage
        if stage = invalid or stage = "" then
            stage = "unknown"
        end if
        m.top.errorDetail = "Live TV task error in " + stage + ": " + LiveTvTaskErrorText(e)
        ? "LIVETV task exception stage=" + stage + " detail=" + m.top.errorDetail
        ' Mirror the failure onto the resolve channel too: a resolve run that
        ' throws must surface via resolveStatus (the scene observes that field
        ' on resolve tasks, never "status"), and resolveError is written BEFORE
        ' the resolveStatus write per the observer-ordering rule above.
        m.top.resolveError = m.top.errorDetail
        m.top.status = 98
        m.top.resolveStatus = 11
    end try
    m.top.control = "stop"
end sub

' Resolve one premium channel id into a fresh playable stream URL.
' resolveId in; resolvedUrl + resolveStatus out (200 ok / 11 failed).
' resolveError is set BEFORE the resolveStatus write so the alwaysNotify
' observer reads it (same ordering rule as errorDetail, file header).
' NOTE: the endpoint answers HTTP 200 even for { success: false }, so the
' verdict comes from CineVidParseStreamResponse(), never the HTTP code.
sub RunCineVidResolve()
    chanId = m.top.resolveId
    if chanId = invalid then
        chanId = ""
    end if
    chanId = chanId.Trim()
    api = CineVidStreamApiUrl(chanId)
    if api = "" then
        m.top.resolveError = "Premium channel resolve: missing channel id"
        m.top.resolveStatus = 11
        return
    end if
    ? "LIVETV resolve begin id=" + chanId
    ' 25s, not 12s: measured 2026-09-26 across the app's own curated lineup,
    ' /api/stream/ answers in ~180-250ms for a healthy channel but takes
    ' 20.7s and 21.3s for some (FOX, Fox Sports 1). The old 12s budget threw
    ' those away as "unreachable" and the scene silently zapped off them.
    res = LiveTvFetchText(api, 25000)
    body = res.body
    if not LiveTvBodyUsable(body) then
        m.top.resolveError = "Premium channel unreachable (HTTP " + res.status.ToStr() + ")"
        m.top.resolveStatus = 11
        return
    end if
    streamUrl = CineVidParseStreamResponse(body)
    if streamUrl = "" then
        m.top.resolveError = "Premium channel has no stream right now (offline or token refused)"
        m.top.resolveStatus = 11
        return
    end if
    m.top.resolvedUrl = streamUrl
    ? "LIVETV resolve ok id=" + chanId
    m.top.resolveStatus = 200
end sub

' Premium (cinevid.st) lineup run: channels only. Cinevid has no XMLTV
' guide, so EPG modes never touch the network here and set an empty EPG
' (the scene renders "No program info" for these channels). Cache:
' tmp:/cinevid_channels.json + tmp:/cinevid_meta.json { cinevidAt },
' TTL CineVidCacheTtlSec(); forceRefresh bypasses it. Status codes reuse
' the free-path contract: 200 ok, 11 fetch failed, 12 unparseable.
sub RunCineVidLineup(wantChannels as Boolean, pivot as Integer)
    if not wantChannels then
        m.top.epg = {}
        m.top.status = 200
        return
    end if
    if not m.top.forceRefresh then
        m.liveTvStage = "cinevid-cache"
        if LiveTvServeCinevidCache(pivot) then
            return
        end if
    end if
    m.liveTvStage = "cinevid-channels"
    channels = LiveTvLoadCinevidChannels()
    if channels = invalid then
        return
    end if
    m.top.channels = channels
    m.top.epg = {}
    m.top.status = 200
end sub

' Serve a fresh premium lineup cache. Returns true when fields were
' populated (caller stops the task). Separate tmp:/ files from the free
' lineup cache so switching sources never crosses streams.
function LiveTvServeCinevidCache(pivot as Integer) as Boolean
      meta = LiveTvCacheReadJson("cinevid_meta.json")
      if meta = invalid or type(meta) <> "roAssociativeArray" then
          return false
      end if
      ' Rows cached before language/status were kept on the record have no
      ' such fields, so serving them would show an empty category line for
      ' hours (the TTL is long). Refuse any payload without the current
      ' schema and let the fetch below re-parse.
      if LiveTvToInt(SafeGet(meta, "cinevidSchema", 0)) <> LiveTvCinevidCacheSchema() then
          ? "LIVETV cinevid cache rejected: schema mismatch"
          return false
      end if
      at = LiveTvToInt(SafeGet(meta, "cinevidAt", 0))
    if at <= 0 or (pivot - at) > CineVidCacheTtlSec() then
        return false
    end if
    cached = LiveTvCacheReadJson("cinevid_channels.json")
    if cached = invalid or type(cached) <> "roArray" or cached.count() = 0 then
        return false
    end if
    m.top.channels = cached
    m.top.epg = {}
    m.top.fromCache = true
    m.top.status = 200
    ? "LIVETV cinevid cache served count=" + cached.count().ToStr()
    return true
end function

' Fetch + curate the premium lineup. Returns the channel array, or
' invalid after setting status/errorDetail (terminal failure).
function LiveTvLoadCinevidChannels() as Dynamic
    res = LiveTvFetchText(CineVidChannelsUrl(), 25000)
    body = res.body
    if not LiveTvBodyUsable(body) then
        m.top.errorDetail = "Premium channels unreachable (HTTP " + res.status.ToStr() + ") - check your network connection, then press BACK and retry"
        m.top.status = 11
        return invalid
    end if
    if LiveTvLooksGzipped(body) then
        m.top.errorDetail = "Premium channels unparseable: feed arrived still gzipped and BrightScript cannot gunzip - press BACK and retry later"
        m.top.status = 12
        return invalid
    end if
    parsed = CineVidParseChannels(body)
    if parsed.count() = 0 then
        m.top.errorDetail = "Premium channels unparseable: no usable channels in the index (feed shape changed) - press BACK and retry later"
        m.top.status = 12
        return invalid
    end if
    LiveTvCacheWrite("cinevid_channels.json", FormatJson(parsed))
    LiveTvStampMetaFile("cinevid_meta.json", "cinevidAt", LiveTvNowSec())
    ? "LIVETV cinevid lineup curated=" + parsed.count().ToStr()
    return parsed
end function

' Build a safe catch message: the exception object shape is firmware
' dependent, so never assume e.Message is a usable string (reading a
' missing key is fine, but concatenating invalid would throw inside the
' handler and hide the real status).
function LiveTvTaskErrorText(e as Dynamic) as String
    detail = "Live TV task error"
    if e <> invalid then
        msg = invalid
        if type(e) = "roAssociativeArray" and e.DoesExist("Message") then
            msg = e["Message"]
        end if
        if msg <> invalid and (type(msg) = "String" or type(msg) = "roString") and msg <> "" then
            detail = detail + ": " + msg
        end if
    end if
    return detail
end function

' Serve a fresh tmp:/ cache when it covers the requested mode. Returns true
' when fields were populated from cache (caller then stops the task).
function LiveTvServeCache(wantChannels as Boolean, wantEpg as Boolean, pivot as Integer) as Boolean
    meta = LiveTvCacheReadJson("livetv_meta.json")
    if meta = invalid or type(meta) <> "roAssociativeArray" then
        return false
    end if
    ' Written by an older build: the payload shape no longer matches what
    ' this build's parser/scene expects (see LiveTvCacheSchema), so refuse it
    ' instead of serving stale data.
    if LiveTvToInt(SafeGet(meta, "schema", 0)) <> LiveTvCacheSchema() then
        return false
    end if
    ttl = LiveTvCacheTtlSec()
    ok = true
    if wantChannels then
        chanAt = LiveTvToInt(SafeGet(meta, "channelsAt", 0))
        chanCache = LiveTvCacheReadJson("livetv_channels.json")
        if chanAt <= 0 or (pivot - chanAt) > ttl then
            ok = false
        else if chanCache = invalid or type(chanCache) <> "roArray" or chanCache.count() = 0 then
            ok = false
        else
            ' Renumber on serve too: a cache written by an older build still
            ' carries sparse Samsung chno (1000+); the 1..N contract is
            ' display-level, so it is enforced at hand-off, not just at fetch.
            for i = 0 to chanCache.count() - 1
                if chanCache[i] <> invalid and type(chanCache[i]) = "roAssociativeArray" then
                    chanCache[i].chNo = i + 1
                end if
            end for
            m.top.channels = chanCache
        end if
    end if
    ' Seed now/next from the cached lineup's own `programs` arrays. Without
    ' this the channels-only cache hit (wantEpg=false) returned status 200
    ' with an EMPTY epg field, so every reload opened the grid on genre-only
    ' labels. A valid epg cache below still overwrites this with <desc> text.
    if ok and wantChannels and type(m.top.channels) = "roArray" and m.top.channels.count() > 0 then
        seedEpg = LiveTvLineupEpg(m.top.channels, pivot)
        if seedEpg.count() > 0 then
            m.top.epg = seedEpg
            ? "LIVETV epg seeded from cached lineup channels=" + seedEpg.count().ToStr()
        end if
    end if
    if ok and wantEpg then
        epgAt = LiveTvToInt(SafeGet(meta, "epgAt", 0))
        epgCache = LiveTvCacheReadJson("livetv_epg.json")
        if epgAt <= 0 or (pivot - epgAt) > ttl then
            ok = false
        else if epgCache = invalid or type(epgCache) <> "roAssociativeArray" then
            ok = false
        else
            m.top.epg = epgCache
        end if
    end if
    if ok then
        m.top.fromCache = true
        m.top.status = 200
        return true
    end if
    return false
end function

' Fetch + parse + curate the channel lineup. PRIMARY: the JSON index
' (.channels.json) via LiveTvParseChannels. FALLBACK (primary yields no
' usable channels): the XMLTV feed via LiveTvParseChannelsFromXmltv — the
' fetched body is stashed on m.liveTvXmlBody so LiveTvLoadEpg reuses the
' same download instead of fetching the ~3MB feed twice. When the lineup
' came from JSON the body is NOT stashed (no <programme> blocks there) and
' the guide fetches its own us.xml. Returns the curated array, or invalid
' after setting status/errorDetail (terminal failure).
function LiveTvLoadChannels(chanUrl as String, capCount as Integer) as Dynamic
    res = LiveTvFetchGuideBody(chanUrl, LiveTvEpgFallbackUrl(), 20000, 15000)
    body = res.body
    if not LiveTvBodyUsable(body) then
        m.top.errorDetail = "Live TV lineup unreachable (HTTP " + res.status.ToStr() + ") - check your network connection, then press BACK and retry"
        m.top.status = 11
        return invalid
    end if
    if LiveTvLooksGzipped(body) then
        m.top.errorDetail = "Live TV lineup unparseable: feed arrived still gzipped and BrightScript cannot gunzip - press BACK and retry later"
        m.top.status = 12
        return invalid
    end if
    parsed = LiveTvParseChannels(body)
    fromXml = false
    if parsed.count() = 0 then
        if Instr(1, body, "<channel") <= 0 then
            m.top.errorDetail = "Live TV lineup unparseable: no usable channels in the index (feed shape changed) - press BACK and retry later"
            m.top.status = 12
            return invalid
        end if
        parsed = LiveTvParseChannelsFromXmltv(body)
        if parsed.count() = 0 then
            m.top.errorDetail = "Live TV lineup unparseable: channel blocks found but no usable titles - press BACK and retry later"
            m.top.status = 12
            return invalid
        end if
        fromXml = true
    end if
    curated = LiveTvCurateChannels(parsed, capCount)
    if curated.count() = 0 then
        m.top.errorDetail = "Live TV lineup curated to zero channels - press BACK and retry later"
        m.top.status = 12
        return invalid
    end if
    ' 2026-09-23: renumber sequentially 1..N (user request "ch # 1-9999 for
    ' simple sake"). Grid order is unchanged (input is chNo-sorted); only the
    ' displayed numbers change, so cable-style order survives without the
    ' sparse 1000+ Samsung numbering.
    for i = 0 to curated.count() - 1
        curated[i].chNo = i + 1
    end for
    if fromXml then
        m.liveTvXmlBody = body
        ? "LIVETV lineup from XMLTV raw=" + parsed.count().ToStr() + " curated=" + curated.count().ToStr()
    else
        m.liveTvXmlBody = ""
        ? "LIVETV lineup from JSON index curated=" + curated.count().ToStr()
    end if
    LiveTvCacheWrite("livetv_channels.json", FormatJson(curated))
    LiveTvStampMeta("channelsAt", LiveTvNowSec())
    return curated
end function

' Fetch + parse the XMLTV guide for the allowlist. Reuses the body already
' downloaded by LiveTvLoadChannels when present (same-run fast path); only
' fetches when running standalone (mode "epg" / cold EPG cache). Returns the
' epg AA, or invalid after setting status/errorDetail (terminal failure).
function LiveTvLoadEpg(guideUrl as String, wanted as Object, pivot as Integer) as Dynamic
    body = ""
    if LiveTvBodyUsable(m.liveTvXmlBody) then
        body = m.liveTvXmlBody
        ? "LIVETV epg reusing guide body len=" + body.Len().ToStr()
    else
        res = LiveTvFetchGuideBody(guideUrl, LiveTvEpgFallbackUrl(), 20000, 15000)
        body = res.body
        if not LiveTvBodyUsable(body) then
            m.top.errorDetail = "Live TV guide unreachable (HTTP " + res.status.ToStr() + ") - channels still work, guide needs a network retry"
            m.top.status = 21
            return invalid
        end if
    end if
    if LiveTvLooksGzipped(body) then
        m.top.errorDetail = "Live TV guide unparseable: feed arrived still gzipped and BrightScript cannot gunzip"
        m.top.status = 22
        return invalid
    end if
    if Instr(1, body, "<programme") <= 0 then
        m.top.errorDetail = "Live TV guide unparseable: feed has no programme blocks (feed shape changed) - press BACK and retry later"
        m.top.status = 22
        return invalid
    end if
    epg = LiveTvParseEpg(body, wanted, pivot)
    if epg.count() = 0 then
        m.top.errorDetail = "Live TV guide has no programmes for these channels right now - check the device clock or retry later"
        m.top.status = 22
        return invalid
    end if
    LiveTvCacheWrite("livetv_epg.json", FormatJson(epg))
    LiveTvStampMeta("epgAt", LiveTvNowSec())
    ? "LIVETV epg channels=" + epg.count().ToStr()
    return epg
end function

' Fetch a plain body (JSON index or XMLTV guide): primary first, fallback
' second. Returns { status, body } where body is always a String ("" when
' both fetches fail), so callers can branch on LiveTvBodyUsable() without
' risking an exception on a non-string payload.
function LiveTvFetchGuideBody(primaryUrl as String, fallbackUrl as String, primaryMs as Integer, fallbackMs as Integer) as Object
    res = LiveTvFetchText(primaryUrl, primaryMs)
    if res.status = 200 and LiveTvBodyUsable(res.body) then
        ? "LIVETV fetch ok len=" + res.body.Len().ToStr() + " url=" + primaryUrl
        return res
    end if
    ? "LIVETV fetch primary failed status=" + res.status.ToStr() + " url=" + primaryUrl
    if fallbackUrl <> invalid and fallbackUrl <> "" and fallbackUrl <> primaryUrl then
        back = LiveTvFetchText(fallbackUrl, fallbackMs)
        if back.status = 200 and LiveTvBodyUsable(back.body) then
            ? "LIVETV fetch fallback ok len=" + back.body.Len().ToStr() + " url=" + fallbackUrl
            return back
        end if
        ? "LIVETV fetch fallback failed status=" + back.status.ToStr() + " url=" + fallbackUrl
        return { status: back.status, body: "" }
    end if
    return { status: res.status, body: "" }
end function

' True only when body is a non-empty BrightScript string. Every Len/Instr/
' parse touch in this task is gated on this, so binary/invalid payloads can
' only produce 11/12/21/22, never an exception (99).
function LiveTvBodyUsable(body as Dynamic) as Boolean
    if body = invalid then
        return false
    end if
    if type(body) <> "String" and type(body) <> "roString" then
        return false
    end if
    return body.Len() > 0
end function

' GET helper mirroring HttpGetText (async roUrlEvent so status codes work),
' plus EnableEncodings(true) for transparent gzip inflation and a caller
' timeout. Runs on the task thread only: roUrlTransfer cannot be created on
' the render thread. Returns { status, body }.
function LiveTvFetchText(url as String, timeoutMs as Integer) as Object
    ' Entry print BEFORE any object setup: if anything in the setup below ever
    ' throws, this line still proves the run got here.
    ? "LIVETV fetch begin url=" + url
    ut = CreateObject("roUrlTransfer")
    ' Standard Roku CA bundle (audit finding): without it, HTTPS hosts whose
    ' chain is not in the firmware default trust store fail as generic
    ' status-0 "unreachable" errors.
    ut.SetCertificatesFile("common:/certs/ca-bundle.crt")
    ut.EnableEncodings(true)
    ut.SetUrl(url)
    port = CreateObject("roMessagePort")
    ut.SetMessagePort(port)
    started = ut.AsyncGetToString()
    ? "LIVETV fetch started=" + started.ToStr() + " url=" + url
    if not started then
        return { status: 0, body: "" }
    end if
    waitMs = timeoutMs
    if waitMs <= 0 then
        waitMs = 20000
    end if
    event = wait(waitMs, port)
    if event = invalid then
        ? "LIVETV fetch timeout url=" + url
        ut.AsyncCancel()
        return { status: 0, body: "" }
    end if
    et = type(event)
    if et = "roUrlEvent" then
        if event.getInt() = 1 then
            code = event.getResponseCode()
            txt = event.getString()
            ' Binary or otherwise undecodable payloads must never surface as
            ' invalid/non-string: coerce here so every caller sees a String.
            if txt = invalid then
                txt = ""
            end if
            if type(txt) <> "String" and type(txt) <> "roString" then
                txt = ""
            end if
            return { status: code, body: txt }
        end if
        ? "LIVETV fetch incomplete int=" + event.getInt().ToStr() + " url=" + url
    else
        ? "LIVETV fetch unexpected event type=" + et + " url=" + url
    end if
    return { status: 0, body: "" }
end function

' ------------------------------------------------------------------
' Streaming TV Guides fallback source (streamingtvguides.com).
' Server-rendered HTML guide pages (verified scraping recipe):
'   /Samsung-TV-Plus/Guide = the CURRENT 4-hour window;
'   <section class="guide-shell" data-start="ISO-UTC-Z" ...>
'   <div class="guide-row"> per channel: <a class="channel-cell"
'   href="/Channel/SLUG"><span>Name</span></a> + program-track with
'   <button class="program-block" style="left:X%;width:Y%;"
'   data-program-title="..." data-program-description="...">...
' Times: start = windowStart + left% x 144s (1% = 2.4min of the 4h
' window); duration = width% x 144s. Empty attributes are BARE (no "=").
' Keys are NORMALIZED channel names; the scene falls back to name lookup.
' ------------------------------------------------------------------

sub RunStvgGuide()
    url = "https://streamingtvguides.com/Samsung-TV-Plus/Guide"
    ? "LIVETV stvg fetch begin url=" + url
    res = LiveTvFetchText(url, 20000)
    if res.status <> 200 or not LiveTvBodyUsable(res.body) then
        m.top.errorDetail = "Streaming TV Guides unreachable (HTTP " + res.status.ToStr() + ") - channels still work"
        m.top.status = 21
        return
    end if
    m.liveTvStage = "stvg-parse"
    epg = LiveTvParseStvg(res.body)
    if epg.count() = 0 then
        m.top.errorDetail = "Streaming TV Guides unparseable: no guide rows (feed shape changed)"
        m.top.status = 22
        return
    end if
    ? "LIVETV stvg parsed channels=" + epg.count().ToStr()
    m.top.epg = epg
    m.top.status = 200
end sub

' HTML entity unescape for guide names/descriptions. Entity strings are
' built via Chr(38) (&) so no authoring/transport step can ever decode
' them into the literals they name (a decoded " broke the literal
' once already).
function LiveTvStvgUnescape(s as String) as String
    amp = Chr(38)
    out = s
    out = out.Replace(amp + "amp;", amp)
    out = out.Replace(amp + "#39;", "'")
    out = out.Replace(amp + "quot;", Chr(34))
    out = out.Replace(amp + "lt;", "<")
    out = out.Replace(amp + "gt;", ">")
    out = out.Replace(amp + "nbsp;", " ")
    return out
end function

' Read an HTML attribute value: find marker (e.g. "data-program-title="),
' read to the closing quote, unescape. Returns "" when the marker is
' absent or the attribute is BARE (empty attrs have no "=").
function LiveTvStvgAttrVal(html as String, marker as String, fromPos as Integer) as String
    at = Instr(fromPos, html, marker)
    if at <= 0 then return ""
    valStart = at + Len(marker)
    if valStart > html.Len() then return ""
    if Mid(html, valStart, 1) <> Chr(34) then return ""
    closeAt = Instr(valStart + 1, html, Chr(34))
    if closeAt <= 0 then return ""
    return LiveTvStvgUnescape(Mid(html, valStart + 1, closeAt - valStart - 1))
end function

' Parse a numeric HTML style value ("left:12.889%") after a marker.
' Returns 0.0 when absent/malformed.
function LiveTvStvgStyleFloat(html as String, marker as String, fromPos as Integer) as Float
    at = Instr(fromPos, html, marker)
    if at <= 0 then return 0.0
    cp = at + Len(marker)
    num = ""
    while cp <= html.Len()
        ch = Mid(html, cp, 1)
        if (ch >= "0" and ch <= "9") or ch = "." then
            num = num + ch
        else
            exit while
        end if
        cp = cp + 1
    end while
    if num = "" then return 0.0
    return Val(num)
end function

' (LiveTvStvgNormKey lives in LiveTv.brs: the scene's name-based EPG
' fallback needs it too, and it is a pure string helper - thread-safe.)

' ISO-8601 Z ("2026-09-25T00:00:00Z") -> epoch seconds. 0 when malformed.
function LiveTvStvgIsoEpoch(iso as String) as Integer
    if iso = invalid or iso.Len() < 19 then return 0
    dt = CreateObject("roDateTime")
    dt.FromISO8601String(iso)
    epoch = dt.AsSeconds()
    if epoch <= 0 then return 0
    return epoch
end function

' Parse the guide page into {normKey: {programs, now, next}}.
function LiveTvParseStvg(body as String) as Object
    epg = {}
    if not LiveTvBodyUsable(body) then return epg
    if Instr(1, body, "guide-row") <= 0 then return epg
    ' 4-hour window start (ISO UTC) from the guide-shell section. The
    ' attribute may sit BEFORE or AFTER class="guide-shell" in the tag, so
    ' scan a short head window that reaches back over the tag's own opening.
    winStart = 0
    shellAt = Instr(1, body, "guide-shell")
    if shellAt > 0 then
        headFrom = shellAt - 500
        if headFrom < 1 then headFrom = 1
        head = Mid(body, headFrom, shellAt - headFrom + 20)
        winStart = LiveTvStvgIsoEpoch(LiveTvStvgAttrVal(head, "data-start=", 1))
        if winStart <= 0 then
            winStart = LiveTvStvgIsoEpoch(LiveTvStvgAttrVal(body, "data-start=", 1))
        end if
    end if
    if winStart <= 0 then return epg
    q = Chr(34)
    rowMarker = "<div class=" + q + "guide-row"
    btnMarker = "<button class=" + q + "program-block"
    scanPos = 1
    guard = 0
    while true
        guard = guard + 1
        if guard > 20000 then exit while
        rowAt = Instr(scanPos, body, rowMarker)
        if rowAt <= 0 then exit while
        nextRowAt = Instr(rowAt + 1, body, rowMarker)
        if nextRowAt <= 0 then
            slice = Mid(body, rowAt)
        else
            slice = Mid(body, rowAt, nextRowAt - rowAt)
        end if
        ' Channel name: first channel-cell's span inside the row.
        cellAt = Instr(1, slice, "channel-cell")
        chanName = ""
        if cellAt > 0 then
            spanAt = Instr(cellAt, slice, "<span>")
            if spanAt > 0 then
                spanEnd = Instr(spanAt, slice, "</span>")
                if spanEnd > 0 then
                    chanName = LiveTvStvgUnescape(Mid(slice, spanAt + 6, spanEnd - spanAt - 6))
                end if
            end if
        end if
        key = LiveTvStvgNormKey(chanName)
        if key <> "" then
            progs = []
            btnPos = 1
            bGuard = 0
            while true
                bGuard = bGuard + 1
                if bGuard > 2000 then exit while
                btnAt = Instr(btnPos, slice, btnMarker)
                if btnAt <= 0 then exit while
                btnEnd = Instr(btnAt, slice, "</button>")
                if btnEnd <= 0 then exit while
                btnPos = btnEnd + 9
                ' Parse INSIDE this button's own markup: an attribute or
                ' style that is absent on the block must not fall through
                ' and pick up the next program's values.
                chunk = Mid(slice, btnAt, btnEnd - btnAt)
                title = LiveTvStvgAttrVal(chunk, "data-program-title=", 1)
                if title = "" then
                    title = LiveTvStvgAttrVal(chunk, "title=", 1)
                end if
                desc = LiveTvStvgAttrVal(chunk, "data-program-description=", 1)
                leftPct = LiveTvStvgStyleFloat(chunk, "left:", 1)
                widthPct = LiveTvStvgStyleFloat(chunk, "width:", 1)
                startSec = winStart + Int(leftPct * 144.0)
                stopSec = startSec + Int(widthPct * 144.0)
                if title <> "" and stopSec > startSec then
                    if desc.Len() > 180 then
                        desc = Left(desc, 180) + "..."
                    end if
                    prog = { title: title, start: startSec, desc: desc }
                    prog["stop"] = stopSec
                    progs.Push(prog)
                end if
            end while
            if progs.count() > 0 then
                LiveTvSortProgramsByStart(progs)
                snap = LiveTvNowNext(progs, 0)
                epg[key] = { programs: progs, now: snap.now, next: snap.next }
            end if
        end if
        if nextRowAt > 0 then
            scanPos = nextRowAt
        else
            exit while
        end if
    end while
    return epg
end function

' tmp:/ cache file helpers. tmp:/ is outside the registry by design.

function LiveTvCachePath(name as String) as String
    return "tmp:/" + name
end function

function LiveTvCacheReadJson(name as String) as Dynamic
    ' First-boot cache miss: ReadAsciiFile on a missing file is caught and
    ' treated as a miss (refetch). (roPathExists does not exist on this
    ' firmware — a guard using it threw on every load.)
    try
        text = ReadAsciiFile(LiveTvCachePath(name))
    catch e
        return invalid
    end try
    if text = invalid or text = "" then
        return invalid
    end if
    parsed = JsonParseSafe(text)
    if parsed = invalid then
        ' A corrupted/foreign tmp:/ cache file silently degrades to a cache
        ' miss (refetch) - but always say so on the console for the next
        ' debug round.
        ? "LIVETV cache unreadable name=" + name + " len=" + text.Len().ToStr()
    end if
    return parsed
end function

sub LiveTvCacheWrite(name as String, text as String)
    if text = invalid or text = "" then
        return
    end if
    ok = WriteAsciiFile(LiveTvCachePath(name), text)
    ' Comparison form, not `not ok`: safe even if the firmware ever returned
    ' invalid here (comparisons with invalid never throw).
    if ok <> true then
        ? "LIVETV cache write failed name=" + name
    end if
end sub

' Record one timestamp into tmp:/livetv_meta.json, preserving the other key.
sub LiveTvStampMeta(key as String, epochSec as Integer)
    LiveTvStampMetaFile("livetv_meta.json", key, epochSec)
end sub

' Cache schema version. Bump whenever the SHAPE or CONTENT of a cached
' payload changes, not just when the fetch code does.
'
' Symptom this fixes: a livetv_epg.json written by a build whose programs
' carried no `desc` key was still considered fresh by LiveTvServeCache, so
' the app kept serving a description-less guide for the whole cache TTL
' (until a reboot that dropped tmp:/) and every program description on the
' TV read "No program info" even though the live parser produced desc
' correctly. A schema mismatch is treated as a cache miss so the new shape
' is fetched once instead of waiting out the old timestamp.
  function LiveTvCacheSchema() as Integer
      return 2
  end function
  
  ' Same idea for the premium lineup, which lives in its own pair of tmp:/
  ' files and so is NOT covered by LiveTvCacheSchema(). Bump this whenever
  ' CineVid.brs starts keeping a new field on a channel record: schema 2 added
  ' language + status, which the browse card and the fullscreen banner both
  ' read, and a schema-1 row would render as a blank category line.
  function LiveTvCinevidCacheSchema() as Integer
      return 2
  end function
  
' Record one timestamp into an arbitrary tmp:/ meta file (used by both the
' free FAST cache and the premium cinevid cache), preserving sibling keys.
sub LiveTvStampMetaFile(metaName as String, key as String, epochSec as Integer)
    meta = LiveTvCacheReadJson(metaName)
    if meta = invalid or type(meta) <> "roAssociativeArray" then
        meta = {}
    end if
      meta[key] = epochSec
      ' Stamp the schema on every write so the serve-side check above can
      ' reject payloads from a build that predates a shape change.
      if metaName = "livetv_meta.json" then
          meta["schema"] = LiveTvCacheSchema()
      end if
      if metaName = "cinevid_meta.json" then
          meta["cinevidSchema"] = LiveTvCinevidCacheSchema()
      end if
    LiveTvCacheWrite(metaName, FormatJson(meta))
end sub

' ------------------------------------------------------------------
' SUDO MOVIES virtual channel (Feature 2). One first-class guide channel
' ("Sudo Movies") playing the latest TMDB trending movies back-to-back via
' VixSrc streams. All network I/O stays on this task thread.
'
' Modes:
'   "sudo"        -> channels + epg + sudoMovies out, status 200 (or 11/12).
'                    The movie list comes from TMDB trending/movie/day (the
'                    same feed as home row 0). tmdbKey in (interface field,
'                    defaults to AppConstants().tmdbDefaultKey); pivot is
'                    nowSec or the device clock. Each movie gets a fabricated
'                    ~2h guide slot counting forward from just before now, so
'                    the first movie always covers the pivot and the scene's
'                    existing now/next snapshot works unchanged.
'   "sudoresolve" -> resolveId (TMDB id) in; resolvedUrl + resolveStatus out
'                    (200 ok / 11 failed), resolveError set BEFORE the status
'                    write per the observer-ordering rule in the file header.
' Cache: tmp:/sudo_movies2.json ({ at, anchor, movies, channels }), TTL 6h.
'        The guide is rebuilt from movies+anchor on every serve, never replayed.
' ------------------------------------------------------------------

function SudoTmdbKey() as String
    key = m.top.tmdbKey
    if key = invalid or key = "" then
        key = AppConstants().tmdbDefaultKey
    end if
    return key
end function

function SudoPivotSec() as Integer
    pivot = m.top.nowSec
    if pivot = invalid or pivot <= 0 then
        pivot = LiveTvNowSec()
    end if
    return pivot
end function

sub RunSudoLineup()
    pivot = SudoPivotSec()
    if not m.top.forceRefresh then
        m.liveTvStage = "sudo-cache"
        if SudoServeCache(pivot) then
            return
        end if
    end if
    m.liveTvStage = "sudo-fetch"
    movies = SudoLoadTrending(SudoTmdbKey())
    if movies = invalid then
        return
    end if
    if movies.count() = 0 then
        m.top.errorDetail = "Sudo Movies guide empty - TMDB returned no trending titles"
        m.top.status = 12
        return
    end if
    SudoPublish(movies, pivot)
end sub

' Fetch TMDB trending movies of the day into lean records
' ({ tmdbId, title, overview, year, mediaType }). Returns the array, or
' invalid after setting status/errorDetail (terminal failure).
function SudoLoadTrending(key as String) as Dynamic
    url = AppConstants().tmdbBase + "/trending/movie/day"
    res = HttpGetText(url, TmdbHeaders(key))
    body = res.body
    if not LiveTvBodyUsable(body) then
        m.top.errorDetail = "Sudo Movies lineup unreachable (HTTP " + res.status.ToStr() + ") - guide still works, Sudo Movies needs a network retry"
        m.top.status = 11
        return invalid
    end if
    if LiveTvLooksGzipped(body) then
        m.top.errorDetail = "Sudo Movies lineup unparseable: feed arrived still gzipped and BrightScript cannot gunzip"
        m.top.status = 12
        return invalid
    end if
    parsed = TmdbParseMovies(body)
    lean = []
    for each rec in parsed
        if rec <> invalid and type(rec) = "roAssociativeArray" then
            ' Movie-channel guard: TmdbParseMovies also emits TV records when
            ' present - a TV id resolved via /api/movie/{id} would 404, so skip.
            if SafeStr(rec, "mediaType", "") <> "tv" and SafeStr(rec, "tmdbId", "") <> "" then
                lean.Push({
                    tmdbId: SafeStr(rec, "tmdbId", ""),
                    title: SafeStr(rec, "title", "Movie"),
                    overview: SafeStr(rec, "overview", ""),
                    year: SafeStr(rec, "year", ""),
                    mediaType: "movie"
                })
                if lean.count() >= 20 then
                    exit for
                end if
            end if
        end if
    end for
    ? "LIVETV sudo trending movies=" + lean.count().ToStr()
    return lean
end function

' Publish one virtual channel + fabricated EPG + movie list onto the task
' fields and the tmp:/ cache. The guide is aligned to the SAME fixed epoch
' anchor the scene uses (m.liveTvSudoAnchor): slot = (now-anchor)\7200, and
' slot i plays movie ((slots+i) mod total). Because the anchor never moves,
' the published guide re-derives to exactly the movie LiveTvSudoSchedule()
' will join, on every device and every visit.
sub SudoPublish(movies as Object, pivot as Integer)
    m.top.sudoMovies = movies
    ch = {
        id: "sudo-movies",
        title: "Sudo Movies",
        thumbnail: "",
        url: "",
        epgId: "sudo-movies",
        genre: "Sudo Movies",
        genreId: "sudo",
        chNo: 1,
        description: "A continuous stream of the latest trending movies.",
        source: "sudo"
    }
    channels = [ch]
    anchor = SudoAnchorSec()
    epg = SudoBuildEpg(movies, anchor, pivot)
    m.top.channels = channels
    m.top.epg = epg
    LiveTvCacheWrite("sudo_movies2.json", FormatJson({ at: pivot, anchor: anchor, movies: movies, channels: channels }))
    ? "LIVETV sudo published movies=" + movies.count().ToStr() + " anchor=" + anchor.ToStr()
    m.top.status = 200
end sub

' Fixed epoch anchor for the artificial-live schedule. The scene always
' writes it into the task before a run; the literal here is only a safe
' fallback so a stale caller cannot produce a schedule anchored at 0.
function SudoAnchorSec() as Integer
    anchor = m.top.sudoAnchor
    if anchor = invalid or anchor <= 0 then anchor = 1790000000
    return anchor
end function

' Build the fabricated guide from the movie queue + fixed anchor. Programs
' form a contiguous total*7200s window starting at the anchor-aligned slot
' that contains `pivot`, so the first program always covers "now" and the
' order matches the scene's slot math. Returns the epg assocarray keyed by
' the virtual channel's epgId.
function SudoBuildEpg(movies as Object, anchor as Integer, pivot as Integer) as Object
    epg = {}
    total = movies.count()
    if total <= 0 then return epg
    slots = (pivot - anchor) \ 7200
    if slots < 0 then slots = 0
    idx0 = slots mod total
    programs = []
    for i = 0 to total - 1
        mv = movies[(idx0 + i) mod total]
        st2 = anchor + (slots + i) * 7200
        en2 = st2 + 7200
        prog = { title: SafeStr(mv, "title", "Movie"), start: st2, desc: SudoMovieDesc(mv) }
        prog["stop"] = en2
        programs.Push(prog)
    end for
    snap = LiveTvNowNext(programs, pivot)
    epg["sudo-movies"] = { programs: programs, now: snap.now, next: snap.next }
    return epg
end function

' Guide description for one sudo movie: year + truncated overview (ASCII only).
function SudoMovieDesc(mv as Object) as String
    yr = SafeStr(mv, "year", "")
    ov = SafeStr(mv, "overview", "")
    if ov.Len() > 180 then
        ov = Left(ov, 180) + "..."
    end if
    if yr <> "" and ov <> "" then
        return "(" + yr + ") " + ov
    end if
    if ov <> "" then
        return ov
    end if
    if yr <> "" then
        return "Trending movie (" + yr + ")."
    end if
    return "Trending movie from Sudo Movies."
end function

' Serve a fresh sudo cache. Returns true when fields were populated.
' The cached guide is NOT trusted as-is: it is rebuilt from the cached movie
' list + anchor against THIS pivot, so a cache written hours ago still lines
' up with the movie the scene is about to join.
function SudoServeCache(pivot as Integer) as Boolean
    cached = LiveTvCacheReadJson("sudo_movies2.json")
    if cached = invalid or type(cached) <> "roAssociativeArray" then
        return false
    end if
    at = LiveTvToInt(SafeGet(cached, "at", 0))
    if at <= 0 or (pivot - at) > 21600 then
        return false
    end if
    movies = SafeGet(cached, "movies", invalid)
    channels = SafeGet(cached, "channels", invalid)
    if movies = invalid or type(movies) <> "roArray" or movies.count() = 0 then
        return false
    end if
    if channels = invalid or type(channels) <> "roArray" or channels.count() = 0 then
        return false
    end if
    anchor = LiveTvToInt(SafeGet(cached, "anchor", 0))
    if anchor <= 0 then anchor = SudoAnchorSec()
    m.top.sudoMovies = movies
    m.top.channels = channels
    m.top.epg = SudoBuildEpg(movies, anchor, pivot)
    m.top.fromCache = true
    m.top.status = 200
    ? "LIVETV sudo cache served movies=" + movies.count().ToStr() + " anchor=" + anchor.ToStr()
    return true
end function

' Resolve one TMDB movie id to a playable VixSrc HLS URL (same 3-step
' pattern as VixSrcTask.brs: api -> embed page -> master playlist).
' resolveError is set BEFORE the resolveStatus write so the alwaysNotify
' observer reads it. Single bounded attempt, never throws outward.
sub RunSudoResolve()
    tmdbId = m.top.resolveId
    if tmdbId = invalid then
        tmdbId = ""
    end if
    tmdbId = tmdbId.Trim()
    if tmdbId = "" then
        m.top.resolveError = "Sudo Movies resolve: missing title id"
        m.top.resolveStatus = 11
        return
    end if
    ? "LIVETV sudo resolve begin tmdb=" + tmdbId
    url = SudoVixResolve(tmdbId)
    if url = "" then
        m.top.resolveError = "Sudo Movies title has no stream right now - skipping"
        m.top.resolveStatus = 11
        return
    end if
    m.top.resolvedUrl = url
    ? "LIVETV sudo resolve ok tmdb=" + tmdbId
    m.top.resolveStatus = 200
end sub

function SudoVixResolve(tmdbId as String) as String
    ua = { "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36" }
    apiUrl = "https://vixsrc.to/api/movie/" + tmdbId
    res = HttpGetText(apiUrl, ua)
    if res.status <> 200 or not LiveTvBodyUsable(res.body) then
        return ""
    end if
    src = SudoExtractJsonString(res.body, "src")
    if src = "" then
        return ""
    end if
    src = src.Replace("\/", "/")
    if Left(src, 1) = "/" then
        src = "https://vixsrc.to" + src
    end if
    refH = { "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36", "Referer": "https://vixsrc.to/" }
    page = HttpGetText(src, refH)
    if page.status <> 200 or not LiveTvBodyUsable(page.body) then
        return ""
    end if
    html = page.body
    mp = Instr(1, html, "window.masterPlaylist")
    chunk = html
    if mp > 0 then
        chunk = Mid(html, mp, 2000)
    end if
    tok = SudoExtractJsValue(chunk, "'token'")
    exp = SudoExtractJsValue(chunk, "'expires'")
    purl = SudoExtractJsValue(chunk, "url")
    if tok = "" or purl = "" then
        purl = SudoExtractJsonString(chunk, "url")
        if purl = "" then
            purl = SudoExtractJsonString(html, "url")
        end if
    end if
    if purl = "" then
        return ""
    end if
    master = purl
    if tok <> "" then
        sep = "?"
        if Instr(1, master, "?") > 0 then
            sep = "&"
        end if
        master = master + sep + "token=" + tok
        if exp <> "" then
            master = master + "&expires=" + exp
        end if
        master = master + "&h=1"
    end if
    chk = HttpGetText(master, refH)
    if chk.status <> 200 or not LiveTvBodyUsable(chk.body) then
        return ""
    end if
    if Instr(1, chk.body, "#EXTM3U") = 0 then
        return ""
    end if
    return master
end function

function SudoExtractJsonString(body as String, key as String) as String
    if body = invalid or body = "" then
        return ""
    end if
    if key = invalid or key = "" then
        return ""
    end if
    pat = Chr(34) + key + Chr(34)
    i = Instr(1, body, pat)
    if i = 0 then
        return ""
    end if
    j = Instr(i + Len(pat), body, ":")
    if j = 0 then
        return ""
    end if
    k = Instr(j + 1, body, Chr(34))
    if k = 0 then
        return ""
    end if
    m2 = Instr(k + 1, body, Chr(34))
    if m2 = 0 then
        return ""
    end if
    return Mid(body, k + 1, m2 - k - 1)
end function

function SudoExtractJsValue(chunk as String, key as String) as String
    if chunk = invalid or chunk = "" then
        return ""
    end if
    if key = invalid or key = "" then
        return ""
    end if
    i = Instr(1, chunk, key)
    if i = 0 then
        return ""
    end if
    j = Instr(i + Len(key), chunk, ":")
    if j = 0 then
        return ""
    end if
    p = j + 1
    n = Len(chunk)
    while p <= n and (Mid(chunk, p, 1) = " " or Mid(chunk, p, 1) = Chr(9))
        p = p + 1
    end while
    if p > n then
        return ""
    end if
    q = Mid(chunk, p, 1)
    if q = "'" or q = Chr(34) then
        m2 = Instr(p + 1, chunk, q)
        if m2 = 0 then
            return ""
        end if
        return Mid(chunk, p + 1, m2 - p - 1)
    end if
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
