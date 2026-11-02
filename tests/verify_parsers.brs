' Regression tests for the Urban / reanime parsing layer.
'
' HOW TO RUN (needs the npm `brs` interpreter; no Roku or network needed -
' every fixture below is captured live HTML checked in under fixtures/):
'   brs components/tests/verify_parsers.brs -r components/tests/fixtures
'
' WHY THIS EXISTS: the parsers previously passed "syntax is fine" while
' silently returning ZERO records - a green build with an empty row. Every
' case below asserts on returned VALUES, not on parse success.

sub Main()
    fails = 0
    fails = fails + TestCatalog()
    fails = fails + TestAnimeRecords()
    fails = fails + TestAnchors()
    fails = fails + TestPlaceholderGuard()
    fails = fails + TestOkRuExtract()
    fails = fails + TestVidmolyExtract()
    fails = fails + TestEntityDecode()
    fails = fails + TestByteToHex()
    fails = fails + TestYoutubeEncode()

    print ""
    if fails = 0 then
        print "RESULT: ALL TESTS PASSED"
    else
        print "RESULT: " + fails.ToStr() + " FAILURE(S)"
    end if
end sub

function Expect(cond as Boolean, label as String) as Integer
    if cond then
        print "  pass  " + label
        return 0
    end if
    print "  FAIL  " + label
    return 1
end function

function TestCatalog() as Integer
    print ""
    print "TestCatalog: baked urban episode rows"
    f = 0
    rows = UrbanCatalogRows()
    f = f + Expect(rows.count() = 4, "4 catalog rows (got " + rows.count().ToStr() + ")")
    if rows.count() = 0 then return f
    r = rows[0]
    ' Keys the generic row builder and OnRowSelected read. Missing mediaType
    ' used to throw on the render thread when the user pressed OK.
    for each k in ["tmdbId", "mediaType", "season", "episode", "title", "poster",
                   "backdrop", "year", "overview", "rating", "runtime", "genres",
                   "source", "okId", "vidmolyId", "voeId", "playmogoId"]
        f = f + Expect(r.DoesExist(k), "record has key " + k)
    end for
    f = f + Expect(SafeT(r, "mediaType", "") = "tv", "mediaType is tv")
    f = f + Expect(SafeT(r, "source", "") = "urban", "source is urban")
    f = f + Expect(SafeT(r, "tmdbId", "") = "", "tmdbId empty (not a TMDB title)")
    f = f + Expect(SafeT(r, "okId", "") <> "", "okId populated")
    f = f + Expect(SafeT(r, "vidmolyId", "") <> "", "vidmolyId populated")
    f = f + Expect(SafeT(r, "poster", "") <> "", "poster populated")
    ' Ids must differ per provider - that is the whole point of the fix.
    ' BrightScript does not allow a bare expression as a function argument,
    ' so the comparison is assigned first. The npm brs interpreter accepts
    ' the inline form, which is why this slipped through until it was run
    ' through brighterscript (the compiler that actually targets Roku).
    distinct = SafeT(r, "okId", "") <> SafeT(r, "vidmolyId", "")
    f = f + Expect(distinct, "okId and vidmolyId are distinct")
    ' Lookup
    ep = UrbanEpisodeByOkId(SafeT(rows[2], "okId", ""))
    f = f + Expect(ep <> invalid, "UrbanEpisodeByOkId finds a known id")
    f = f + Expect(UrbanEpisodeByOkId("nope") = invalid, "unknown id returns invalid")
    return f
end function

function TestAnimeRecords() as Integer
    print ""
    print "TestAnimeRecords: reanime.to listing record shape"
    f = 0
    body = ReadAsciiFile("pkg:/reanime.html")
    list = UrbanParseAnimeBody(body)
    f = f + Expect(list.count() > 0, "parsed at least 1 record (got " + list.count().ToStr() + ")")
    if list.count() = 0 then return f
    r = list[0]
    for each k in ["tmdbId", "mediaType", "season", "episode", "title", "poster",
                   "backdrop", "year", "overview", "rating", "runtime", "genres", "source"]
        f = f + Expect(r.DoesExist(k), "record has key " + k)
    end for
    f = f + Expect(SafeT(r, "mediaType", "") = "tv", "mediaType is tv")
    f = f + Expect(SafeT(r, "source", "") = "reanime", "source is reanime")
    f = f + Expect(SafeT(r, "title", "") <> "", "title non-empty")
    f = f + Expect(SafeT(r, "poster", "") <> "", "poster non-empty")
    f = f + Expect(Len(SafeT(r, "year", "")) = 4, "year is 4 digits (got '" + SafeT(r, "year", "") + "')")
    f = f + Expect(SafeT(r, "genres", "") <> "", "type/genres non-empty (got '" + SafeT(r, "genres", "") + "')")
    f = f + Expect(SafeT(r, "rating", "") <> "", "rating non-empty")
    ' Every record must be openable-or-explained, never a crash.
    bad = 0
    for i = 0 to list.count() - 1
        if not list[i].DoesExist("mediaType") then bad = bad + 1
    end for
    f = f + Expect(bad = 0, "all " + list.count().ToStr() + " records have mediaType")
    return f
end function

' The entity case used to yield zero records with no error anywhere.
function TestAnchors() as Integer
    print ""
    print "TestAnchors: rating glyph as raw UTF-8 and as HTML entity"
    f = 0
    raw = ReadAsciiFile("pkg:/reanime.html")
    ent = ReadAsciiFile("pkg:/reanime_entity.html")
    a = UrbanParseAnimeBody(raw)
    b = UrbanParseAnimeBody(ent)
    f = f + Expect(a.count() > 0, "raw-star form parses")
    f = f + Expect(b.count() > 0, "entity form parses")
    sameCount = a.count() = b.count()
    f = f + Expect(sameCount, "both forms return the same count (" + a.count().ToStr() + " vs " + b.count().ToStr() + ")")
    if a.count() > 0 and b.count() > 0 then
        sameTitle = SafeT(a[0], "title", "") = SafeT(b[0], "title", "")
        f = f + Expect(sameTitle, "same first title")
        sameRating = SafeT(a[0], "rating", "") = SafeT(b[0], "rating", "")
        f = f + Expect(sameRating, "same first rating (" + SafeT(a[0], "rating", "") + " vs " + SafeT(b[0], "rating", "") + ")")
    end if
    return f
end function

' Handing the user a public demo clip is worse than handing them nothing.
function TestPlaceholderGuard() as Integer
    print ""
    print "TestPlaceholderGuard: demo media must be rejected"
    f = 0
    bad = [
        "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4",
        "https://cdn.example.com/BigBuckBunny.mp4",
        "https://media.w3.org/2010/05/sintel/trailer.mp4",
        "https://download.blender.org/peach/bigbuckbunny_movies/BigBuckBunny_320x180.mp4"
    ]
    for each u in bad
        f = f + Expect(UrbanIsPlaceholderMedia(u), "rejected: " + Left(u, 46))
    end for
    good = [
        "https://ok6-3.vkuser.net/video.m3u8?cmd=videoPlayerCdn",
        "https://rr1---sn-abc.googlevideo.com/videoplayback?id=xyz",
        "https://cdn.mixdrop.co/abc/master.m3u8"
    ]
    for each u in good
        f = f + Expect(not UrbanIsPlaceholderMedia(u), "accepted: " + Left(u, 46))
    end for
    return f
end function

function TestOkRuExtract() as Integer
    print ""
    print "TestOkRuExtract: OK.ru data-options -> hlsManifestUrl"
    f = 0
    body = ReadAsciiFile("pkg:/ok_embed.html")
    h = OkRuExtractHls(body)
    f = f + Expect(h <> "", "extracted a URL")
    if h = "" then return f
    f = f + Expect(Left(h, 4) = "http", "absolute http URL")
    f = f + Expect(Instr(1, h, ".m3u8") > 0, "is an m3u8 manifest")
    return f
end function

function TestVidmolyExtract() as Integer
    print ""
    print "TestVidmolyExtract: jwplayer sources -> master.m3u8 with token"
    f = 0
    body = ReadAsciiFile("pkg:/vidmoly_embed.html")
    h = VidmolyExtractHls(body)
    f = f + Expect(h <> "", "extracted a URL")
    if h = "" then return f
    f = f + Expect(Left(h, 4) = "http", "absolute http URL")
    f = f + Expect(Instr(1, h, "master.m3u8") > 0, "points at master.m3u8")
    f = f + Expect(InStr(1, h, "?") > 0, "keeps the auth token query")
    f = f + Expect(Instr(1, h, Chr(34)) = 0 and Instr(1, h, Chr(32)) = 0, "no quote or space in URL")
    return f
end function

function TestEntityDecode() as Integer
    print ""
    print "TestEntityDecode: HTML entity decoding"
    f = 0
    s = UrbanEntityDecode("a&quot;b&quot;c&#39;d&apos;e")
    f = f + Expect(InStr(1, s, Chr(34)) > 0, "decodes &quot;")
    f = f + Expect(InStr(1, s, "'") > 0, "decodes &#39;/&apos;")
    ' BrightScript has no backslash escapes: "\u0026" is the literal six
    ' characters backslash-u-0-0-2-6, which is exactly what a JSON payload
    ' carries when it encodes an ampersand.
    f = f + Expect(UrbanEntityDecode("x\u0026y") = "x&y", "decodes unicode amp escape")
    f = f + Expect(UrbanEntityDecode("a\/b") = "a/b", "decodes escaped slash")
    return f
end function

' Regression: YoutubeTask used BrightScript Hex(), which the Roku language
' reference this channel targets does not define. The channel failed to
' compile, so the whole Youtube feature was dead. ByteToHex does the two
' nibbles by hand and must reproduce Hex() semantics exactly.
function TestByteToHex() as Integer
    print ""
    print "TestByteToHex: hand-rolled percent-encode (replaced Hex())"
    f = 0
    cases = [
        [0, "00"],
        [1, "01"],
        [9, "09"],
        [10, "0A"],
        [15, "0F"],
        [16, "10"],
        [32, "20"],
        [47, "2F"],
        [63, "3F"],
        [65, "41"],
        [127, "7F"],
        [128, "80"],
        [255, "FF"]
    ]
    for each c in cases
        got = ByteToHex(c[0])
        f = f + Expect(got = c[1], "ByteToHex(" + c[0].ToStr() + ") = " + got + " expected " + c[1])
    end for
    ' Out-of-range input must clamp rather than throw on a bad string index.
    lowClamped = ByteToHex(-1)
    f = f + Expect(lowClamped = "00", "clamps negative to 00 (got " + lowClamped + ")")
    highClamped = ByteToHex(999)
    f = f + Expect(highClamped = "FF", "clamps above 255 to FF (got " + highClamped + ")")
    return f
end function

function TestYoutubeEncode() as Integer
    print ""
    print "TestYoutubeEncode: URL percent-encoding"
    f = 0
    plain = YoutubeEncode("abcXYZ019-_.~")
    f = f + Expect(plain = "abcXYZ019-_.~", "unreserved set passes through (got " + plain + ")")
    space = YoutubeEncode("a b")
    f = f + Expect(space = "a%20b", "space -> %20 (got " + space + ")")
    amp = YoutubeEncode("a&b")
    f = f + Expect(amp = "a%26b", "ampersand -> %26 (got " + amp + ")")
    q = YoutubeEncode("q=a/b")
    f = f + Expect(q = "q%3Da%2Fb", "equals and slash encoded (got " + q + ")")
    ' Must never emit a raw space: that truncates the query server-side.
    anySpace = YoutubeEncode("one two three")
    f = f + Expect(InStr(1, anySpace, " ") = 0, "no literal spaces survive")
    empty = YoutubeEncode("")
    f = f + Expect(empty = "", "empty string stays empty")
    return f
end function

' Local safe string read, so the tests do not depend on the app's SafeStr.
function SafeT(rec as Object, key as String, fallback as String) as String
    if rec = invalid then return fallback
    if not rec.DoesExist(key) then return fallback
    v = rec[key]
    if v = invalid then return fallback
    return v.ToStr()
end function