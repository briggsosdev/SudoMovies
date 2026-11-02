function ScrapeUrl(providerBase as String, title as String, year as String, tmdbId as String, target as String) as String
    url = providerBase + "/scrape?type=movie"
    url = url + "&title=" + UrlEncode(title)
    url = url + "&releaseYear=" + UrlEncode(year)
    url = url + "&tmdbId=" + UrlEncode(tmdbId)
    url = url + "&target=" + UrlEncode(target)
    return url
end function

function ScrapeEmbedUrl(providerBase as String, id as String, url as String, target as String) as String
    result = providerBase + "/scrape/embed?id=" + UrlEncode(id)
    result = result + "&url=" + UrlEncode(url)
    result = result + "&target=" + UrlEncode(target)
    return result
end function

' Converts a RunOutput (completed event payload) into an array of
' playable candidates. Skips sources that need multi-request flows.
function RunOutputToCandidates(runOutput as Object) as Object
    candidates = []
    if runOutput = invalid then
        return candidates
    end if
    sources = SafeGet(runOutput, "sources", [])
    for each source in sources
        if SourceIsPlayable(source) then
            cand = StreamToCandidate(source)
            if cand <> invalid then
                candidates.Push(cand)
            end if
        end if
    end for
    return candidates
end function

function SourceIsPlayable(source as Object) as Boolean
    if source = invalid then
        return false
    end if
    requests = SafeGet(source, "requests", [])
    if requests <> invalid and requests.count() > 0 then
        return false
    end if
    url = SafeStr(source, "url", "")
    if url = "" then
        return false
    end if
    return true
end function

' Converts a stream-ish record (a source or an embed result's stream) into a candidate.
function StreamToCandidate(stream as Object) as Object
    if stream = invalid then
        return invalid
    end if
    url = SafeStr(stream, "url", "")
    if url = "" then
        return invalid
    end if
    streamType = SafeStr(stream, "type", "file")
    if streamType <> "hls" and streamType <> "file" then
        streamType = "file"
    end if
    headers = HeadersFromAA(SafeGet(stream, "headers", invalid))
    proxyHeaders = HeadersFromAA(SafeGet(stream, "proxyHeaders", invalid))
    for each k in proxyHeaders.Keys()
        if headers.DoesExist(k) = false then
            headers[k] = proxyHeaders[k]
        end if
    end for
    name = SafeStr(stream, "name", "Source")
    quality = SafeStr(stream, "quality", "")
    cand = {
        name: name,
        quality: quality,
        type: streamType,
        url: url,
        headers: headers,
        title: ""
    }
    cand.label = name
    if quality <> "" then
        cand.label = name + " - " + quality
    end if
    cand.score = QualityScore(quality) * 10
    if streamType = "hls" then
        cand.score = cand.score + 2
    else
        cand.score = cand.score + 1
    end if

    ' Attach subtitle tracks (OpenSubtitles & friends) surfaced by the provider.
    ' Roku plays these via ContentNode.SubtitleTracks (srt/ttml/dfxp).
    captions = SafeGet(stream, "captions", [])
    subs = []
    for each cap in captions
        capUrl = SafeStr(cap, "url", "")
        if capUrl <> "" then
            lang = SafeStr(cap, "lang", "en")
            label = SafeStr(cap, "label", "")
            if label = "" then
                label = lang
            end if
            capType = SafeStr(cap, "type", "")
            subs.Push({
                url: capUrl,
                lang: lang,
                label: label,
                captionType: capType,
                formatScore: CaptionFormatScore(capType)
            })
        end if
    end for
    if subs.count() > 0 then
        cand.subtitles = subs
        cand.score = cand.score + 1
    end if
    return cand
end function

function CaptionFormatScore(captionType as String) as Integer
    lower = LCase(captionType)
    if lower = "srt" then
        return 40
    end if
    if lower = "ttml" then
        return 30
    end if
    if lower = "dfxp" then
        return 20
    end if
    if lower = "vtt" then
        return 10
    end if
    return 5
end function

function QualityScore(qualityStr as String) as Integer
    lower = LCase(qualityStr)
    if lower = "4k" or lower = "2160" or lower = "uhd" or Instr(1, lower, "2160") > 0 or Instr(1, lower, "4k") > 0 then
        return 2160
    end if
    if Instr(1, lower, "1080") > 0 then
        return 1080
    end if
    if Instr(1, lower, "720") > 0 then
        return 720
    end if
    if Instr(1, lower, "480") > 0 then
        return 480
    end if
    if Instr(1, lower, "360") > 0 then
        return 360
    end if
    return 0
end function

' Sorts candidates best-first.
function RankCandidates(candidates as Object) as Object
    for i = 0 to candidates.count() - 1
        for j = i + 1 to candidates.count() - 1
            if candidates[j].score > candidates[i].score then
                tmp = candidates[i]
                candidates[i] = candidates[j]
                candidates[j] = tmp
            end if
        end for
    end for
    return candidates
end function

' If no direct sources came back, try resolving up to maxCount embeds.
function ResolveEmbeds(providerBase as String, runOutput as Object, target as String, maxCount as Integer) as Object
    candidates = []
    if runOutput = invalid then
        return candidates
    end if
    embeds = SafeGet(runOutput, "embeds", [])
    count = 0
    for each embed in embeds
        if count >= maxCount then
            exit for
        end if
        count = count + 1
        id = SafeStr(embed, "id", "")
        embedUrl = SafeStr(embed, "url", "")
        if id <> "" and embedUrl <> "" then
            url = ScrapeEmbedUrl(providerBase, id, embedUrl, target)
            res = HttpGetText(url, {})
            if res.status = 200 then
                out = ParseSseCompleted(res.body)
                if out <> invalid then
                    stream = SafeGet(out, "stream", invalid)
                    if stream <> invalid then
                        cand = StreamToCandidate(stream)
                        if cand <> invalid then
                            candidates.Push(cand)
                        end if
                    end if
                end if
            end if
        end if
    end for
    return RankCandidates(candidates)
end function