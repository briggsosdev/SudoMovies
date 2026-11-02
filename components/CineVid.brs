' CineVid.brs — pure data-layer helpers for the premium CineVid lineup.
'
' Source: cinevid.st public channel index + per-channel stream resolver.
'   VERIFIED 2026-09-23 (plain HTTPS GET from a PC, Roku/DVP UA accepted):
'     /api/channels -> HTTP 200, application/json, shape
'       { total_channels: 1038, last_updated: "...", channels: [ { id, name,
'         country, language, category, logo, status, slug, key, sources } ] }
'       with logo RELATIVE ("/logo/TNT_Sports_1-UK.png"), status "online"/
'       "offline", and sources = { tms, tvn, stream, cdn-live } booleans.
'       Distribution verified: 966 online / 72 offline; 391 online+English;
'       337 of those carry sources.stream=true (tvn-only entries cannot be
'       resolved and are dropped at parse time).
'     /api/stream/{channel_id} -> HTTP 200, application/json,
'       { success: true, streamUrl: "/stream/{token}" } on success;
'       { success: false, streamUrl: null } for offline/unresolvable (NOTE:
'       still HTTP 200 — the parser must check success, not the code).
'     /stream/{token} -> HTTP 200, application/vnd.apple.mpegurl, a LIVE
'       media playlist (rolling 4s segments, relative /stream/segment?url=...
'       &token=... URIs resolved against the cinevid.st origin). Verified
'       with a Roku/DVP-147.1E04111A UA: accepted without Referer/cookies.
'   Streams are NEVER resolved at lineup time: every channel record carries
'   url "" and source "cinevid", and the scene resolves a FRESH token per
'   tune through LiveTvTask mode "resolve" (tokens are short-lived, so a
'   cached token would break re-tunes; a fresh resolve costs one ~40-byte
'   JSON call).
'
' THREADING: pure functions, no SceneGraph dependency, no network I/O
'   (fetching lives in LiveTvTask.brs), nothing touches the registry.
'
' DEPENDENCIES: SafeGet / SafeStr (components/Tmdb.brs), JsonParseSafe
'   (components/Json.brs). Any component that includes this file must also
'   include those two scripts (see components/tasks/LiveTvTask.xml).
'
' All function names use the CineVid prefix to avoid collisions (LiveTv*,
' SafeGet, SafeStr, JsonParseSafe, HttpGetText, Tmdb*, Febbox*, Vix*, ...).

function CineVidHost() as String
    return "https://cinevid.st"
end function

' Canonical lineup endpoint (verified 2026-09-23: HTTP 200, ~200KB JSON).
function CineVidChannelsUrl() as String
    return CineVidHost() + "/api/channels"
end function

' Per-channel stream resolver (fresh token per call; see file header).
function CineVidStreamApiUrl(chanId as String) as String
    if chanId = invalid or chanId = "" then
        return ""
    end if
    return CineVidHost() + "/api/stream/" + chanId
end function

' The API returns relative paths for logos and the stream token
' ("/logo/x.png", "/stream/{token}"); make them absolute. Absolute inputs
' pass through unchanged so the parser never has to special-case.
function CineVidAbsoluteUrl(path as String) as String
    if path = invalid then
        return ""
    end if
    p = path.Trim()
    if p = "" then
        return ""
    end if
    if Len(p) >= 4 and Left(p, 4) = "http" then
        return p
    end if
    if Left(p, 1) <> "/" then
        p = "/" + p
    end if
    return CineVidHost() + p
end function

' Safety cap on the curated premium lineup (337 online English stream=true
' channels existed at verification; cap guards a feed explosion).
function CineVidMaxChannels() as Integer
    return 400
end function

' Channel-list cache TTL: the lineup is stable, tokens are per-tune, so a
' 6h poll is plenty (the free FAST lineup polls daily).
function CineVidCacheTtlSec() as Integer
    return 21600
end function

' Curated display order: sports-first (the recognizable premium names),
' unknown categories sink to the bottom instead of interleaving.
function CineVidCategoryOrder() as Object
    return ["Sports", "Movies", "Entertainment", "News", "Documentary", "Kids", "General"]
end function

' Rank of a category inside CineVidCategoryOrder() (case-insensitive);
' anything unknown ranks last (99) and then sorts by name.
function CineVidCategoryRank(cat as String) as Integer
    if cat = invalid or cat = "" then
        return 99
    end if
    want = LCase(cat.Trim())
    order = CineVidCategoryOrder()
    for i = 0 to order.count() - 1
        if LCase(order[i]) = want then
            return i
        end if
    end for
    return 99
end function

' Truthiness for JSON booleans that may arrive as Boolean, Integer or String.
function CineVidFlag(v as Dynamic) as Boolean
    if v = invalid then
        return false
    end if
    t = type(v)
    if t = "Boolean" or t = "roBoolean" then
        return v = true
    end if
    if t = "Integer" or t = "roInt" then
        return v <> 0
    end if
    if t = "String" or t = "roString" then
        s = LCase(v.Trim())
        return s = "true" or s = "1" or s = "yes"
    end if
    return false
end function

' True when ANY of the source flags the upstream currently populates is set.
'
' SCHEMA CHANGE (live-verified 2026-10-03, https://cinevid.st/api/channels,
' HTTP 200 / 504 channels): the filter used to require sources.stream, and
' that flag is now false on ALL 504 records - the whole Premium row went
' empty. The upstream moved its volume onto other keys:
'
'   status=online         322
'   + language=English    220
'   + sources.stream      0     <-- dead key, removed upstream
'   tvn                   166
'   cdn-live               62
'
' Accepting any true source flag keeps the lineup populated and lets the
' per-channel stream resolver decide whether a given channel actually plays.
' A channel that cannot resolve surfaces as a playback error on that tile,
' which is honest; an empty Premium row is not.
function CineVidHasPlayableSource(sources as Dynamic) as Boolean
    if sources = invalid then
        return false
    end if
    if type(sources) <> "roAssociativeArray" then
        return false
    end if
    for each key in ["stream", "tvn", "cdn-live", "cdn_live"]
        if sources.DoesExist(key) then
            if CineVidFlag(sources[key]) then
                return true
            end if
        end if
    end for
    return false
end function

' Parse the channels index into scene-shaped records:
'   { id, title, thumbnail, url: "", epgId: "", genre: category, chNo: n,
'     description: "", source: "cinevid" }
' Curation (verified against the live feed, see file header):
'   - status must be "online"
'   - language must be English (keeps the lineup recognizable instead of
'     7-language Eurosport duplicates)
'   - at least one source flag set (see CineVidHasPlayableSource: the old
'     sources.stream-only test now matches zero channels)
'   - dedupe by normalized name (first occurrence wins)
'   - sort by category rank, then name; chNo is sequential grid order
'     (synthetic - the item tile shows the category tag instead of a
'     channel number, see LiveTvChannelItem.brs)
' Returns [] when the body is not the expected JSON shape.
function CineVidParseChannels(body as String) as Object
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
    chans = SafeGet(data, "channels", invalid)
    if chans = invalid or type(chans) <> "roArray" then
        return result
    end if
    seen = {}
    cap = CineVidMaxChannels()
    for each entry in chans
        if entry <> invalid and type(entry) = "roAssociativeArray" then
            statusStr = LCase(SafeStr(entry, "status", ""))
            if statusStr = "online" then
                lang = LCase(SafeStr(entry, "language", ""))
                if lang = "english" then
                    hasStream = CineVidHasPlayableSource(SafeGet(entry, "sources", invalid))
                    if hasStream then
                        title = SafeStr(entry, "name", "")
                        if title <> "" then
                            normTitle = LCase(title.Trim())
                            if not seen.DoesExist(normTitle) then
                                seen[normTitle] = true
                                idStr = SafeStr(entry, "id", "")
                                if idStr <> "" then
                                    ' The channel index has no description
                                    ' field, so a real per-channel line is
                                    ' composed from what it does carry
                                    ' (category/language/country) — the
                                    ' info card previously showed one
                                    ' identical sentence for every channel.
                                    cat = SafeStr(entry, "category", "")
                                    lang = SafeStr(entry, "language", "")
                                    country = SafeStr(entry, "country", "")
                                    desc = ""
                                    if cat <> "" and lang <> "" and country <> "" then
                                        desc = "Live " + LCase(cat) + " channel in " + lang + " (" + country + ")."
                                    else if cat <> "" then
                                        desc = "Live " + LCase(cat) + " channel."
                                    end if
                                          result.Push({
                                              id: idStr,
                                              title: title,
                                              thumbnail: CineVidAbsoluteUrl(SafeStr(entry, "logo", "")),
                                              url: "",
                                              epgId: "",
                                              genre: cat,
                                              chNo: 0,
                                              description: desc,
                                              country: country,
                                              language: lang,
                                              status: SafeStr(entry, "status", ""),
                                              source: "cinevid"
                                          })
                                    if result.count() >= cap then
                                        exit for
                                    end if
                                end if
                            end if
                        end if
                    end if
                end if
            end if
        end if
    end for
    return CineVidSortByCategoryThenName(result)
end function

' Insertion sort: category rank ascending, then title ascending. chNo is
' then stamped as sequential 1..N so the flat grid order matches the sort.
function CineVidSortByCategoryThenName(channels as Object) as Object
    if channels = invalid then
        return []
    end if
    n = channels.count()
    for i = 1 to n - 1
        keyRec = channels[i]
        keyRank = CineVidCategoryRank(SafeStr(keyRec, "genre", ""))
        keyName = LCase(SafeStr(keyRec, "title", ""))
        j = i - 1
        while j >= 0
            cur = channels[j]
            curRank = CineVidCategoryRank(SafeStr(cur, "genre", ""))
            curName = LCase(SafeStr(cur, "title", ""))
            swapIt = false
            if curRank > keyRank then
                swapIt = true
            else if curRank = keyRank and curName > keyName then
                swapIt = true
            end if
            if not swapIt then
                exit while
            end if
            channels[j + 1] = channels[j]
            j = j - 1
        end while
        channels[j + 1] = keyRec
    end for
    for i = 0 to n - 1
        channels[i].chNo = i + 1
    end for
    return channels
end function

' Parse a /api/stream/{id} response into an absolute playable URL.
' Returns "" for every failure mode (missing success, success=false,
' null/empty streamUrl, bad JSON) so the caller only checks for "".
' NOTE: the endpoint answers HTTP 200 even for { success: false }, so the
' HTTP status alone must never be trusted here.
function CineVidParseStreamResponse(body as String) as String
    if body = invalid or body = "" then
        return ""
    end if
    if LiveTvLooksGzipped(body) then
        return ""
    end if
    data = JsonParseSafe(body)
    if data = invalid or type(data) <> "roAssociativeArray" then
        return ""
    end if
    if not CineVidFlag(SafeGet(data, "success", invalid)) then
        return ""
    end if
    return CineVidAbsoluteUrl(SafeStr(data, "streamUrl", ""))
end function
