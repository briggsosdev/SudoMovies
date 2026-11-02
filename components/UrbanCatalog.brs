' UrbanCatalog.brs - VERIFIED embed catalog for the Urban homescreen row.
'
' PURE DATA: no roUrlTransfer, no network, no SceneGraph nodes. Safe to
' include from a render-thread component (HomeScene) AND from a task
' component (UrbanTask), which is why it lives in its own file instead of
' inside UrbanStreams.brs (that one is task-only by contract).
'
' WHY BAKED INSTEAD OF FETCHED: the previous lineup source
' (brokensilenze.mom/api/channels) returns HTTP 404 on every path tried
' (/api/channels, /channels, /api/channels.json, /api/lineup.json, /api),
' so the Urban row rendered an "Unavailable" tile forever. These entries are
' the provider IDs that were LIVE-VERIFIED end to end (embed page HTTP 200 +
' manifest HTTP 200 + #EXTM3U), so they are the only Urban content that can
' actually be promised to play.
'
' PROVIDER IDS ARE PER-SITE AND NOT INTERCHANGEABLE: one episode carries a
' different id at every provider. Passing an OK.ru id to the Vidmoly resolver
' (the old single-episodeId signature) silently 404s, which is why every
' entry below keeps all four ids side by side.
'
' NO TITLE IS INVENTED. The source data supplied ids only, so each tile is
' labelled by season/episode rather than guessing a show name.

' Canonical list of verified episodes.
'   { id, season, episode, okId, vidmolyId, voeId, playmogoId }
function UrbanEpisodes() as Object
    return [
        {
            id: "s1e1",
            season: "1",
            episode: "1",
            okId: "15937498778353",
            vidmolyId: "gmucjmfc3qhe",
            voeId: "s8ozxivzy4lg",
            playmogoId: "r4ao6dt3rjmx"
        },
        {
            id: "s1e2",
            season: "1",
            episode: "2",
            okId: "16011628055281",
            vidmolyId: "pdt2x5rhmtqh",
            voeId: "4mbp5oehio3f",
            playmogoId: "fq4m2jo57puo"
        },
        {
            id: "s1e3",
            season: "1",
            episode: "3",
            okId: "16089211996913",
            vidmolyId: "dgqvwgcakgy0",
            voeId: "pu8v8gvqpdvl",
            playmogoId: "kr9xold888aa"
        },
        {
            id: "s1e4",
            season: "1",
            episode: "4",
            okId: "16165024566001",
            vidmolyId: "slldvs1iehfi",
            voeId: "el9rnf7fxuay",
            playmogoId: "5q2wpexp6qc4"
        }
    ]
end function

' Human label for a catalog row: "S1 E1". Deliberately generic - no show
' name is asserted because the source data carried ids only.
function UrbanEpisodeLabel(ep as Object) as String
    if ep = invalid then return "Episode"
    s = UrbanSafeField(ep, "season", "")
    e = UrbanSafeField(ep, "episode", "")
    if s <> "" and e <> "" then
        return "S" + s + " E" + e
    end if
    if e <> "" then
        return "Episode " + e
    end if
    return "Episode"
end function

' Which providers actually resolve for this entry, as a short ASCII list.
' OK.ru and Vidmoly are the verified ones; the rest are listed so the tile
' explains itself instead of looking broken.
function UrbanEpisodeSources(ep as Object) as String
    if ep = invalid then return ""
    out = ""
    if UrbanSafeField(ep, "okId", "") <> "" then out = out + "OK.ru"
    if UrbanSafeField(ep, "vidmolyId", "") <> "" then
        if out <> "" then out = out + "  "
        out = out + "Vidmoly"
    end if
    return out
end function

' Rows for the home feed. Shaped exactly like a TmdbParseMovies record so
' BuildHomeRowsReal's generic loop can render them with no special case:
'   { tmdbId, mediaType, season, episode, title, poster, year, overview,
'     rating, runtime, genres, backdrop, source, okId, vidmolyId, voeId,
'     playmogoId }
' tmdbId is "" on purpose: these are not TMDB titles, and faking an id would
' make ShowDetails fetch the wrong film. OnRowSelected routes source="urban"
' to the embed resolver instead of the TMDB details flow.
function UrbanCatalogRows() as Object
    rows = []
    eps = UrbanEpisodes()
    for each ep in eps
        if ep <> invalid then
            label = UrbanEpisodeLabel(ep)
            srcs = UrbanEpisodeSources(ep)
            rows.Push({
                tmdbId: "",
                mediaType: "tv",
                season: UrbanSafeField(ep, "season", ""),
                episode: UrbanSafeField(ep, "episode", ""),
                title: label,
                poster: "pkg:/images/tile_reload.png",
                backdrop: "",
                year: "",
                overview: "Verified stream sources: " + srcs,
                rating: "",
                runtime: "",
                genres: "Urban",
                source: "urban",
                okId: UrbanSafeField(ep, "okId", ""),
                vidmolyId: UrbanSafeField(ep, "vidmolyId", ""),
                voeId: UrbanSafeField(ep, "voeId", ""),
                playmogoId: UrbanSafeField(ep, "playmogoId", "")
            })
        end if
    end for
    return rows
end function

' Local, file-local SafeStr: this file is included by components that do not
' all pull in the shared SafeStr helper, and a missing-key read must never
' throw mid-row-build.
function UrbanSafeField(rec as Object, key as String, fallback as String) as String
    if rec = invalid then return fallback
    if not rec.DoesExist(key) then return fallback
    v = rec[key]
    if v = invalid then return fallback
    if type(v) = "String" or type(v) = "roString" then
        return v.ToStr()
    end if
    return v.ToStr()
end function

' Find one catalog entry by its okId (used when a record arrives from a row
' instead of from UrbanCatalogRows). Returns invalid when not found.
function UrbanEpisodeByOkId(okId as String) as Object
    if okId = invalid or okId = "" then return invalid
    for each ep in UrbanEpisodes()
        if ep <> invalid and UrbanSafeField(ep, "okId", "") = okId then
            return ep
        end if
    end for
    return invalid
end function