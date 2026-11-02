sub init()
    m.top.functionName = "RunScrape"
end sub

sub RunScrape()
    ' NOTE: do NOT reset m.top.status here (see FemboxTask.brs comment).
    m.top.progress = "Contacting master scrape endpoint..."
    m.top.candidates = []

    base = m.top.providerApiBase
    target = m.top.target
    if target = "" then
        target = "native"
    end if

    constants = AppConstants()
    maxEmbeds = constants.maxEmbedsToResolve

    try
        url = ScrapeUrl(base, m.top.movieTitle, m.top.releaseYear, m.top.tmdbId, target)
        res = HttpGetText(url, {})
        if res.status <> 200 then
            m.top.errorDetail = "Scrape request failed (HTTP " + res.status.ToStr() + ")"
            m.top.status = 1
            m.top.control = "stop"
            return
        end if

        m.top.progress = ParseSseLastProgress(res.body)
        runOutput = ParseSseCompleted(res.body)
        if runOutput = invalid then
            m.top.errorDetail = "No completed scrape event returned."
            m.top.status = 2
            m.top.control = "stop"
            return
        end if

        candidates = RunOutputToCandidates(runOutput)
        candidates = RankCandidates(candidates)

        if candidates.count() = 0 then
            m.top.progress = "Resolving embed links..."
            candidates = ResolveEmbeds(base, runOutput, target, maxEmbeds)
        end if
        if candidates.count() = 0 then
            ? "Movy fallback"
            mType = "movie"
            mUrl = "https://movy.sx/movie/" + m.top.tmdbId
            mRes = HttpGetText(mUrl, { Referer: "https://movy.sx/" })
            if mRes.status = 200 then
                mMarker = "id=__N_SSG" + Chr(34) + ">"
                mIdx = Instr(1, mRes.body, mMarker)
                if mIdx > 0 then
                    mSp = mIdx + Len(mMarker)
                    mFin = Instr(mSp, mRes.body, "</script>")
                    if mFin > 0 then
                        mJsonStr = Mid(mRes.body, mSp, mFin - mSp)
                        mSsg = ParseJson(mJsonStr)
                        if mSsg <> invalid then
                            mProps = SafeGet(mSsg, "props", invalid)
                            if mProps <> invalid then
                                mPageProps = SafeGet(mProps, "pageProps", invalid)
                                if mPageProps <> invalid then
                                    mMovie = SafeGet(mPageProps, "movie", invalid)
                                    if mMovie <> invalid then
                                        movyUrl = SafeStr(mMovie, "streamUrl", "")
                                        if movyUrl <> "" then
                                            candidates.Push({
                                                name: "Movy",
                                                quality: "",
                                                type: "hls",
                                                url: movyUrl,
                                                headers: { Referer: "https://movy.sx/" },
                                                title: ""
                                            })
                                        end if
                                    end if
                                end if
                            end if
                        end if
                    end if
                end if
            end if
        end if

        if candidates.count() = 0 then
            m.top.errorDetail = "No streamable sources found for this movie."
            m.top.status = 3
            m.top.control = "stop"
            return
        end if

        m.top.candidates = candidates
        m.top.status = 200
    catch e
        ' Defensive message extraction (audit finding): a firmware exception
        ' object without Message would throw INSIDE the catch, skipping the
        ' terminal status write and stranding the modal open forever.
        m.top.errorDetail = "Scrape error: " + TaskErrorText(e)
        m.top.status = 4
    end try

    m.top.progress = ""
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