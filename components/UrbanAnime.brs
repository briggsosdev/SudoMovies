' UrbanAnime.brs ??? PURE PARSING helpers for reanime.to home HTML.
' Render-thread safe: no roUrlTransfer here. The network fetch happens in
' the ApiTask pipeline (HomeScene:FetchNextHomeRow) and the captured body
' is parsed with UrbanParseAnimeBody() in the task-done callback.
'
' LIVE-TESTED (Sep 2026, 8 episodes across 8 anime): reanime.to watch pages
' carry NO video sources, NO .m3u8, NO embed links ??? the site is metadata-
' only right now. Home listing (titles, posters, ratings) IS available.
' Episode playback resolution lives in UrbanVideoEmbed.brs (task thread).

' Parse the reanime.to/home body into record-shaped data:
'   { title, type, year, rating, poster, watchLink: "", source: "reanime" }
' CONFIRMED hero-card structure (from real captured HTML):
'   <span>??? 8.5</span>  <span>TV</span>  <span>2026</span>
'   <img src="https://image.tmdb.org/..." alt="TITLE">
'   <p>description</p>  <button>Watch Now</button>
' Title lives in the img alt attr; poster is the img src. Watch Now buttons
' are JS-driven (no href in static HTML), so watchLink stays empty.
' Returns [] when the body is unusable.
function UrbanParseAnimeBody(body as String) as Object
    result = []
    if body = invalid or body = "" then return result

    ' Anchor on the rating glyph in ANY of the forms a site can ship it:
    ' raw UTF-8 star, decimal entity, or hex entity. Pinning to only the raw
    ' glyph made the whole row silently return zero records the moment the
    ' markup emitted &amp;#9733; instead - a green-looking failure with no
    ' error anywhere.
    ' Cap record count: bounds the work on the render thread and prevents a
    ' repeated-glyph markup change from becoming an unbounded loop.
    cap = UrbanMaxAnimeRecords()
    idx = UrbanNextAnchor(body, 1)
    while idx > 0
        if result.count() >= cap then
            exit while
        end if
        anchorEnd = UrbanAnchorEnd(body, idx)

        ' Rating: the numeric run between the anchor and the closing </span>.
        ratingText = ""
        spanEnd = Instr(anchorEnd, body, "</span>")
        if spanEnd > 0 then
            ratingText = UrbanRatingBetween(body, anchorEnd, spanEnd)
        end if

        ' Scan winBlock: from the anchor to just past the following <p> block.
        winStart = idx
        winEnd = idx + 2500
        if winEnd > body.Len() then winEnd = body.Len()
        winBlock = Mid(body, winStart, winEnd - winStart + 1)

        ' Title + poster from the first <img ...> in the winBlock:
        '   src="https://..." alt="Title"
        titleText = ""
        posterUrl = ""
        imgPos = Instr(1, winBlock, "<img")
        if imgPos > 0 then
            ' src attribute: "src=\"" found at the s; +4 lands ON the opening
            ' quote, so the closing-quote search must start at srcPos + 1.
            srcPos = Instr(imgPos, winBlock, "src=" + Chr(34))
            if srcPos > 0 then
                srcPos = srcPos + 4
                srcEnd = Instr(srcPos + 1, winBlock, Chr(34))
                if srcEnd > 0 then
                    posterUrl = Mid(winBlock, srcPos + 1, srcEnd - srcPos - 1)
                end if
            end if
            ' alt attribute: same off-by-one guard.
            altPos = Instr(imgPos, winBlock, "alt=" + Chr(34))
            if altPos > 0 then
                altPos = altPos + 4
                altEnd = Instr(altPos + 1, winBlock, Chr(34))
                if altEnd > 0 then
                    titleText = Mid(winBlock, altPos + 1, altEnd - altPos - 1).Trim()
                end if
            end if
        end if

        ' Type + year: the two <span> text runs after the rating span.
        ' For each span: find </span>, walk BACK to the preceding > — the
        ' text between them is the span's text content ("TV", "2026").
        ' Searched in BODY coordinates (spanEnd is a body position).
        animeType = ""
        yearText = ""
        if spanEnd > 0 then
            ' +7 skips past the rating's own </span> so t2 lands on the
            ' TYPE span's closer, not the rating's.
            t2 = Instr(spanEnd + 7, body, "</span>")
            if t2 > 0 then
                animeType = SpanTextBefore(body, t2)
                ' Year span: the next </span> after the type span
                y2 = Instr(t2 + 7, body, "</span>")
                if y2 > 0 then
                    yearText = SpanTextBefore(body, y2)
                end if
            end if
            ' Sanity: year must be 4 digits starting 19/20.
            if Len(yearText) <> 4 or (Left(yearText, 2) <> "19" and Left(yearText, 2) <> "20") then
                yearText = ""
            end if
end if

        ' Pushed with the FULL home-record field set, not just the scraped
        ' four. The generic row builder and OnRowSelected read these keys with
        ' dot access in some paths, so a record missing mediaType/tmdbId used
        ' to throw on the render thread the moment the user pressed OK.
        ' tmdbId is intentionally "": reanime.to exposes no TMDB id in the
        ' listing HTML, and inventing one would open the wrong title.
        if titleText <> "" then
            result.Push({
                tmdbId: "",
                mediaType: "tv",
                season: "",
                episode: "",
                title: titleText,
                poster: posterUrl,
                backdrop: "",
                year: yearText,
                overview: "",
                rating: ratingText,
                runtime: "",
                genres: animeType,
                type: animeType,
                watchLink: "",
                source: "reanime"
            })
        end if

if idx + 1 >= body.Len() then exit while
        idx = UrbanNextAnchor(body, idx + 1)
    end while

    return result
end function

' Next rating-anchor position at or after fromPos, across every supported
' glyph form. Returns 0 when none remain.
function UrbanNextAnchor(body as String, fromPos as Integer) as Integer
    if body = invalid or body = "" then return 0
    return UrbanFindNextAnchor(body, fromPos)
end function

' All accepted spellings of the rating glyph.
'
' LIVE (2026-10-03): reanime.to/home is 379,743 bytes and ships the rating as a
' raw UTF-8 U+2605 (16 per page). Note that a Latin-1 reader renders it as
' mojibake - always decode the body as UTF-8 or this anchor silently vanishes.
'
' Anchors are matched with ONE Instr per card via a single pass (see
' UrbanFindNextAnchor) rather than one full-body scan per form: 4 scans x 16
' cards x 379KB is ~24M character comparisons, which is what froze the UI.
function UrbanAnchorForms() as Object
    return [Chr(9733), "&#9733;", "&#x2605;", "&star;"]
end function

' Upper bound on records parsed from one page. The live page carries 16; the
' cap exists so a markup change that makes the glyph repeat thousands of times
' cannot turn the Home row into an unbounded loop that locks the render thread.
function UrbanMaxAnimeRecords() as Integer
    return 40
end function

' Native- Instr anchor search. DO NOT "optimize" this into a per-character
' Mid() loop: Instr is implemented in native code, whereas Mid(body, i, 1)
' runs in the interpreter and allocates a string per character. Replacing four
' native scans with a 377,000-iteration interpreted loop made boot hang on 3 of
' 4 launches - it was ~1000x SLOWER, not faster. Character-count arithmetic
' hides this; only wall-clock on the device shows it.
'
' Four forms x native scan is cheap enough. The 379KB body is bounded instead by
' the record cap in UrbanParseAnimeBody.
function UrbanFindNextAnchor(body as String, fromPos as Integer) as Integer
    if body = invalid or body = "" then return 0
    if fromPos < 1 then fromPos = 1
    best = 0
    for each form in UrbanAnchorForms()
        p = Instr(fromPos, body, form)
        if p > 0 then
            if best = 0 or p < best then best = p
        end if
    end for
    return best
end function

' One past the end of the anchor that starts at idx (anchors differ in
' length, and the rating search has to resume AFTER the whole glyph).
function UrbanAnchorEnd(body as String, idx as Integer) as Integer
    for each form in UrbanAnchorForms()
        if Mid(body, idx, Len(form)) = form then
            return idx + Len(form)
        end if
    end for
    return idx + 1
end function

' Numeric rating between two positions. Takes the first digit run (max 4
' chars) so both "8.5" and "10" survive, and tolerates leftover markup or a
' second glyph between the anchor and the number.
function UrbanRatingBetween(body as String, fromPos as Integer, spanEndPos as Integer) as String
    if spanEndPos <= fromPos then return ""
    seg = Mid(body, fromPos, spanEndPos - fromPos)
    n = Len(seg)
    i = 1
    startAt = 0
    while i <= n
        c = Mid(seg, i, 1)
        if c >= "0" and c <= "9" then
            startAt = i
            exit while
        end if
        i = i + 1
    end while
    if startAt = 0 then return ""
    out = ""
    i = startAt
    while i <= n
        c = Mid(seg, i, 1)
        isDigit = (c >= "0" and c <= "9")
        isDot = (c = ".")
        if not isDigit and not isDot then exit while
        out = out + c
        i = i + 1
    end while
    ' Trailing dot (e.g. "8.") is not a rating.
    if Len(out) > 0 and Right(out, 1) = "." then out = Left(out, Len(out) - 1)
    if out = "" then return ""
    return out
end function

' Slug builder for /watch/{slug} URLs (matches reanime.to's kebab-case).
function Slugify(t as String) as String
    if t = invalid then return ""
    t = LCase(t)
    result = ""
    n = Len(t)
    lastDash = false
    for i = 1 to n
        c = Mid(t, i, 1)
        keep = false
        if c >= "0" and c <= "9" then
            keep = true
        else if c >= "a" and c <= "z" then
            keep = true
        else if c = " " or c = "-" or c = "_" or c = "." or c = "," or c = "'" or c = ":" then
            keep = true
            c = "-"
        end if
        if keep then
            if c = "-" and lastDash then
                ' skip duplicate dash
            else
                result = result + c
                lastDash = (c = "-")
            end if
        end if
    end for
    if Left(result, 1) = "-" then result = Mid(result, 2)
    if Right(result, 1) = "-" then result = Left(result, result.Len() - 1)
    return result
end function

' Text content of a span: walk BACK from the </span> position (spanClosePos,
' pointing at "<") to the preceding ">" and return what is between them.
function SpanTextBefore(body as String, spanClosePos as Integer) as String
    if body = invalid or body = "" then return ""
    if spanClosePos = invalid or spanClosePos < 2 then return ""
    p = spanClosePos
    while p > 1
        ch = Mid(body, p - 1, 1)
        if ch = ">" then
            txt = Mid(body, p, spanClosePos - p)
            return txt.Trim()
        end if
        p = p - 1
    end while
    return ""
end function
