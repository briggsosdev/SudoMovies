' DoesExist() belongs to roAssociativeArray/roArray ONLY. roSGNode - which is
' what m.top is inside a Task - exposes hasField()/getField() instead, and a
' String/Integer/boolean has no DoesExist() at all, so calling it on anything
' else raises a runtime error.
'
' WHY THE TYPE CHECK IS HERE. Every other DoesExist() call in this app is
' already guarded (see the `type(x) = "roAssociativeArray"` + DoesExist()
' pairs in Profiles.brs, ArchiveTask.brs, the Task catch handlers, ...).
' SafeGet/SafeStr were the one unguarded pair, and they are the widest helpers
' in the codebase - SafeStr() is called on a plain assocarray, an
' interface field, and (in tasks/YoutubeTask.brs) on the Task node itself:
'     carried = SafeStr(m.top, "trailerKey", "")
' That line threw on the very first field read of RunYoutubeTask, the catch
' turned it into errorDetail, and HomeScene showed the generic "Trailer
' lookup error" for EVERY title instead of a trailer. Degrading to the
' fallback keeps a bad argument harmless, which is the entire point of a
' "safe" getter.
function SafeGet(aa as Object, key as String, fallback) as Dynamic
    if aa = invalid then
        return fallback
    end if
    t = type(aa)
    if t <> "roAssociativeArray" and t <> "roArray" then
        return fallback
    end if
    if aa.DoesExist(key) and aa[key] <> invalid then
        return aa[key]
    end if
    return fallback
end function

function SafeStr(aa as Object, key as String, fallback as String) as String
    v = SafeGet(aa, key, invalid)
    if v = invalid then
        return fallback
    end if
    if type(v) = "roString" or type(v) = "String" then
        return v
    end if
    return v.ToStr()
end function

function TmdbHeaders(key as String) as Object
    return {
        "Authorization": "Bearer " + key,
        "accept": "application/json"
    }
end function

function TmdbSearchUrl(cfg as Object, query as String, page = 1 as Integer) as String
    c = AppConstants()
    url = c.tmdbBase + "/search/multi?query=" + SearchEncode(query) + "&include_adult=false"
    ' TMDB paginates every list endpoint; page 1 is the default.
    if page > 1 then
        url = url + "&page=" + page.ToStr()
    end if
    return url
end function

' Paged TMDB list endpoints report "page" and "total_pages" in the same
' envelope as "results". Read total_pages straight out of the body so any
' paged browse (search, genre, collection) knows how many pages exist
' without a second request. Returns 1 when the field is absent.
function TmdbTotalPages(body as String) as Integer
    if body = invalid or body = "" then return 1
    key = Chr(34) + "total_pages" + Chr(34)
    p = InStr(1, body, key)
    if p < 1 then return 1
    ' p is the 1-based position of the OPENING quote, so p + Len(key) (not
    ' p + Len(key) - 1) is the character right AFTER the closing quote - the
    ' ':' of the real response, "total_pages":500.
    rest = Mid(body, p + Len(key))
    q = InStr(1, rest, ":")
    if q < 1 then return 1
    digits = ""
    ' INDEXING (do not "fix" this - both halves are correct):
    '   InStr() and the Mid() function are 1-based, so q is the colon's
    '   1-based offset inside rest.
    '   String.Mid() is 0-based, so rest.Mid(i - 1, 1) is rest's i-th char.
    ' Loop from q + 1 to start AFTER the colon; i = q would hand the ':' to
    ' the digit test and exit with an empty number.
    for i = q + 1 to rest.Len()
        ch = rest.Mid(i - 1, 1)
        if ch >= "0" and ch <= "9" then
            digits = digits + ch
        else
            exit for
        end if
    end for
    if digits = "" then return 1
    n = Val(digits)
    if n < 1 then return 1
    return n
end function

function TmdbTvSeriesUrl(cfg as Object, tvId as String) as String
    c = AppConstants()
    return c.tmdbBase + "/tv/" + tvId
end function

function TmdbTvSeasonsUrl(cfg as Object, tvId as String) as String
    ' TMDB has no /tv/{id}/season endpoint: the seasons array lives on
    ' the series detail object (/tv/{id}), which also carries episode counts.
    return TmdbTvSeriesUrl(cfg, tvId)
end function

function TmdbTvEpisodesUrl(cfg as Object, tvId as String, seasonNum as Integer) as String
    c = AppConstants()
    return c.tmdbBase + "/tv/" + tvId + "/season/" + seasonNum.ToStr()
end function

' Percent-encoder that uses no components, so it is safe on any thread
' (roUrlTransfer cannot be created on the render thread).
function SearchEncode(value as String) as String
    out = ""
    hex = "0123456789ABCDEF"
    for i = 1 to value.Len()
        ch = value.Mid(i - 1, 1)
        code = Asc(ch)
        if (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or ch = "-" or ch = "_" or ch = "." or ch = "~" then
            out = out + ch
        else if ch = " " then
            out = out + "%20"
        else if code >= 0 and code < 256 then
            out = out + "%" + hex.Mid(code \ 16, 1) + hex.Mid(code MOD 16, 1)
        else
            out = out + "%20"
        end if
    end for
    return out
end function

function TmdbDiscoverUrl(cfg as Object, endpoint as String) as String
    c = AppConstants()
    return c.tmdbBase + "/" + endpoint
end function

function TmdbImageUrl(path as String, size as String) as String
    if path = "" or path = invalid then
        return ""
    end if
    c = AppConstants()
    return c.tmdbImageBase + "/" + size + path
end function

' Single-item detail endpoint path ("movie/123" or "tv/123") used to hydrate
' lean watchlist/resume records into full records before showing details.
function TmdbDetailPath(rec as Object) as String
    mt = SafeStr(rec, "mediaType", "")
    if mt = "" then mt = SafeStr(rec, "m", "movie")
    id = SafeStr(rec, "tmdbId", "")
    if id = "" then id = SafeStr(rec, "id", "")
    if id = "" then return ""
    if mt = "tv" then return "tv/" + id
    return "movie/" + id
end function

' Normalizes a single TMDB detail object (NOT a "results" array) into a full
' record, honoring the requested mediaType (movie/tv).
function TmdbParseDetail(body as String, mediaType as String) as Object
    item = JsonParseSafe(body)
    if item = invalid or type(item) <> "roAssociativeArray" then
        return invalid
    end if
    if mediaType = "tv" then
        return TmdbNormTV(item)
    end if
    return TmdbNormMovie(item)
end function

function TmdbIsTv(item as Object) as Boolean
    mt = SafeStr(item, "media_type", "")
    if mt = "tv" then
        return true
    end if
    if mt = "movie" then
        return false
    end if
    ' Some trending endpoints omit media_type: infer from the record shape.
    if SafeStr(item, "title", "") = "" and SafeStr(item, "name", "") <> "" then
        return true
    end if
    return false
end function

function TmdbParseMovies(body as String) as Object
    result = []
    data = JsonParseSafe(body)
    if data = invalid then
        return result
    end if
    items = SafeGet(data, "results", [])
    for each item in items
        mt = SafeStr(item, "media_type", "")
        if mt = "" or mt = "movie" or mt = "tv" then
            if TmdbIsTv(item) then
                rec = TmdbNormTV(item)
            else
                rec = TmdbNormMovie(item)
            end if
            if rec <> invalid then
                result.Push(rec)
            end if
        end if
    end for
    return result
end function

function TmdbNormTV(item as Object) as Object
    tmdbId = SafeStr(item, "id", "")
    if tmdbId = "" then
        return invalid
    end if
    year = ""
    rd = SafeStr(item, "first_air_date", "")
    if Len(rd) >= 4 then
        year = Left(rd, 4)
    end if
    rec = {
        tmdbId: tmdbId,
        title: SafeStr(item, "name", ""),
        year: year,
        poster: TmdbImageUrl(SafeStr(item, "poster_path", ""), "w342"),
        posterPath: SafeStr(item, "poster_path", ""),
        backdrop: TmdbImageUrl(SafeStr(item, "backdrop_path", ""), "w1280"),
        overview: SafeStr(item, "overview", ""),
        rating: SafeStr(item, "vote_average", ""),
        runtime: "",
        genres: "",
        mediaType: "tv"
    }
    return rec
end function

function TmdbNormMovie(item as Object) as Object
    tmdbId = SafeStr(item, "id", "")
    if tmdbId = "" then
        return invalid
    end if
    year = ""
    rd = SafeStr(item, "release_date", "")
    if Len(rd) >= 4 then
        year = Left(rd, 4)
    end if
    rec = {
        tmdbId: tmdbId,
        title: SafeStr(item, "title", ""),
        year: year,
        poster: TmdbImageUrl(SafeStr(item, "poster_path", ""), "w342"),
        posterPath: SafeStr(item, "poster_path", ""),
        backdrop: TmdbImageUrl(SafeStr(item, "backdrop_path", ""), "w1280"),
        overview: SafeStr(item, "overview", ""),
        rating: SafeStr(item, "vote_average", ""),
        runtime: "",
        genres: "",
        mediaType: "movie"
    }
    return rec
end function