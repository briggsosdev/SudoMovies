' User profiles + per-profile playback resume.
'
' Registry section "profiles" (SEPARATE from the "settings" section used by
' Config.brs, so settings stay intact). One key ("store") holds a JSON object:
'   {
'     active: "<profileId>" | "",
'     profiles: [ { id, name, created, updated } ],   ' max 4
'     resume: { "<profileId>": { "<key>": resumeRec } },
'     watchlist: { "<profileId>": [ { id, m, t } ] }  ' lean, max 60/profile
'   }
' Resume record (kept small for the 32KB per-app registry limit):
'   { t: tmdbId, m: mediaType, s: season, e: episode,
'     p: positionSec, d: durationSec, ti: title(<=60), po: poster(<=200), u: updatedAt }
' Resume key: "movie:<tmdbId>" or "tv:<tmdbId>" or "tv:<tmdbId>:S<season>E<episode>".
' Each profile keeps at most 30 resume points (LRU by updatedAt).
'
' Self-contained: uses only local helpers (no dependency on Tmdb.brs), so it
' can be included by any component. Registry I/O follows the Config.brs pattern
' and already happens on the render thread there, so callers may do the same.

function ProfilesTimeNow() as Integer
    dt = CreateObject("roDateTime")
    return dt.AsSeconds()
end function

function ProfilesStr(aa as Object, key as String, fb as String) as String
    if aa = invalid then return fb
    if not aa.DoesExist(key) then return fb
    v = aa[key]
    if v = invalid then return fb
    if type(v) = "roString" or type(v) = "String" then return v
    return v.ToStr()
end function

function ProfilesInt(aa as Object, key as String, fb as Integer) as Integer
    if aa = invalid then return fb
    if not aa.DoesExist(key) then return fb
    v = aa[key]
    if v = invalid then return fb
    if type(v) = "roInt" or type(v) = "Integer" then return v
    if type(v) = "roFloat" or type(v) = "Float" then return Int(v)
    if type(v) = "roString" or type(v) = "String" then return v.ToInt()
    return fb
end function

function ProfilesEmptyStore() as Object
    return { active: "", profiles: [], resume: {}, watchlist: {} }
end function

function ProfilesLoad() as Object
    store = ProfilesEmptyStore()
    raw = PersistReadRaw("profiles", "store")
    if raw = invalid or raw = "" then return store
    parsed = ParseJson(raw)
    if parsed = invalid or type(parsed) <> "roAssociativeArray" then return store
    if parsed.DoesExist("active") and parsed.active <> invalid then
        store.active = parsed.active.ToStr()
    end if
    if parsed.DoesExist("profiles") and type(parsed.profiles) = "roArray" then
        for each p in parsed.profiles
            if type(p) = "roAssociativeArray" and p.DoesExist("id") and p.id <> invalid then
                store.profiles.Push(p)
            end if
        end for
    end if
    if parsed.DoesExist("resume") and type(parsed.resume) = "roAssociativeArray" then
        store.resume = parsed.resume
    end if
    if parsed.DoesExist("watchlist") and type(parsed.watchlist) = "roAssociativeArray" then
        store.watchlist = parsed.watchlist
    end if
    if store.active <> "" and ProfilesFindIndex(store, store.active) < 0 then
        store.active = ""
    end if
    return store
end function

sub ProfilesSave(store as Object)
    if store = invalid then return
    json = FormatJson(store)
    ' FormatJson returns "" on failure; PersistEnqueue treats "" as DELETE,
    ' so an empty serialization would have wiped the whole store (audit
    ' P0). Bail instead — the previous store stays intact.
    if json = "" then
        ? "PROFILES save aborted: FormatJson failed"
        return
    end if
    PersistEnqueue("profiles", "store", json)
end sub

function ProfilesFindIndex(store as Object, id as String) as Integer
    if store = invalid or id = "" or id = invalid then return -1
    for i = 0 to store.profiles.count() - 1
        p = store.profiles[i]
        if type(p) = "roAssociativeArray" and ProfilesStr(p, "id", "") = id then
            return i
        end if
    end for
    return -1
end function

function ProfilesGetActiveId(store as Object) as String
    if store = invalid then return ""
    if store.active = invalid then return ""
    return store.active
end function

function ProfilesGetActiveName(store as Object) as String
    if store = invalid then return ""
    i = ProfilesFindIndex(store, ProfilesGetActiveId(store))
    if i < 0 then return ""
    return ProfilesStr(store.profiles[i], "name", "")
end function

' Create a profile (max 4). Returns the new id, or invalid when full.
function ProfilesCreate(store as Object, name as String) as Dynamic
    if store = invalid then return invalid
    if store.profiles.count() >= 4 then return invalid
    clean = name
    if clean = invalid then clean = ""
    clean = clean.Trim()
    if clean.Len() > 20 then clean = clean.Left(20)
    if clean = "" then clean = "Profile " + (store.profiles.count() + 1).ToStr()
    now = ProfilesTimeNow()
    id = "p" + now.ToStr()
    if ProfilesFindIndex(store, id) >= 0 then
        id = id + "_" + store.profiles.count().ToStr()
    end if
    store.profiles.Push({ id: id, name: clean, created: now, updated: now })
    if ProfilesGetActiveId(store) = "" then store.active = id
    ProfilesSave(store)
    return id
end function

function ProfilesRename(store as Object, id as String, name as String) as Boolean
    i = ProfilesFindIndex(store, id)
    if i < 0 then return false
    clean = name
    if clean = invalid then clean = ""
    clean = clean.Trim()
    if clean.Len() > 20 then clean = clean.Left(20)
    if clean = "" then return false
    store.profiles[i].name = clean
    store.profiles[i].updated = ProfilesTimeNow()
    ProfilesSave(store)
    return true
end function

function ProfilesDelete(store as Object, id as String) as Boolean
    i = ProfilesFindIndex(store, id)
    if i < 0 then return false
    store.profiles.Delete(i)
    if store.resume.DoesExist(id) then store.resume.Delete(id)
    if store.watchlist <> invalid and store.watchlist.DoesExist(id) then store.watchlist.Delete(id)
    if ProfilesGetActiveId(store) = id then
        store.active = ""
        if store.profiles.count() > 0 then
            store.active = ProfilesStr(store.profiles[0], "id", "")
        end if
    end if
    ProfilesSave(store)
    return true
end function

function ProfilesSetActive(store as Object, id as String) as Boolean
    if ProfilesFindIndex(store, id) < 0 then return false
    store.active = id
    ProfilesSave(store)
    return true
end function

' Key identifying one playable title. Movies: "movie:<id>". TV without a
' concrete episode (e.g. a tv deep link): "tv:<id>". Episodes add ":S<s>E<e>".
function ProfilesResumeKey(rec as Object) as String
    t = ProfilesStr(rec, "tmdbId", "")
    if t = "" then return ""
    mt = ProfilesStr(rec, "mediaType", "movie")
    if mt = "" then mt = "movie"
    s = ProfilesStr(rec, "season", "")
    e = ProfilesStr(rec, "episode", "")
    if mt = "tv" and s <> "" and e <> "" then
        return "tv:" + t + ":S" + s + "E" + e
    end if
    return mt + ":" + t
end function

function ProfilesGetBucket(store as Object, profileId as String) as Object
    if store = invalid or profileId = "" or profileId = invalid then return invalid
    if not store.resume.DoesExist(profileId) then return invalid
    b = store.resume[profileId]
    if type(b) <> "roAssociativeArray" then return invalid
    return b
end function

function ProfilesGetResume(store as Object, profileId as String, rec as Object) as Object
    b = ProfilesGetBucket(store, profileId)
    if b = invalid then return invalid
    key = ProfilesResumeKey(rec)
    if key = "" then return invalid
    if b.DoesExist(key) then return b[key]
    return invalid
end function

' True when ANY episode (or series-level point) exists for a tv series.
function ProfilesSeriesHasResume(store as Object, profileId as String, mediaType as String, tmdbId as String) as Boolean
    b = ProfilesGetBucket(store, profileId)
    if b = invalid then return false
    if tmdbId = "" or tmdbId = invalid then return false
    mt = mediaType
    if mt = "" or mt = invalid then mt = "tv"
    prefix = mt + ":" + tmdbId
    for each k in b
        if Instr(1, k, prefix) = 1 then return true
    end for
    return false
end function

sub ProfilesPutResume(store as Object, profileId as String, meta as Object, posSec as Integer, durSec as Integer)
    if store = invalid or profileId = "" or profileId = invalid then return
    if ProfilesFindIndex(store, profileId) < 0 then return
    key = ProfilesResumeKey(meta)
    if key = "" then return
    b = ProfilesGetBucket(store, profileId)
    if b = invalid then
        b = {}
        store.resume[profileId] = b
    end if
    ti = ProfilesStr(meta, "title", "")
    if ti.Len() > 60 then ti = ti.Left(60)
    po = ProfilesStr(meta, "poster", "")
    if po.Len() > 200 then po = po.Left(200)
    if not b.DoesExist(key) then
        while b.count() >= 30
            oldestK = invalid
            oldestU = 0
            first = true
            for each k in b
                u = 0
                ent = b[k]
                if type(ent) = "roAssociativeArray" then u = ProfilesInt(ent, "u", 0)
                if first or u < oldestU then
                    oldestU = u
                    oldestK = k
                    first = false
                end if
            end for
            if oldestK = invalid then exit while
            b.Delete(oldestK)
        end while
    end if
    b[key] = {
        t: ProfilesStr(meta, "tmdbId", ""),
        m: ProfilesStr(meta, "mediaType", "movie"),
        s: ProfilesStr(meta, "season", ""),
        e: ProfilesStr(meta, "episode", ""),
        p: posSec,
        d: durSec,
        ti: ti,
        po: po,
        u: ProfilesTimeNow()
    }
    ProfilesSave(store)
end sub

sub ProfilesClearResume(store as Object, profileId as String, rec as Object)
    b = ProfilesGetBucket(store, profileId)
    if b = invalid then return
    key = ProfilesResumeKey(rec)
    if key = "" then return
    if b.DoesExist(key) then
        b.Delete(key)
        ProfilesSave(store)
    end if
end sub

' Merge resume identity fields, preferring `pref` (the interface resumeRec)
' and falling back to `fb` (the stream candidate). Used by PlaybackScene so
' the tv-resolve branch (which builds fresh cands) still saves under the
' right tmdbId/season/episode.
function ProfilesMetaForRec(pref as Object, fb as Object) as Object
    meta = { tmdbId: "", mediaType: "movie", season: "", episode: "", title: "", poster: "" }
    for each k in ["tmdbId", "mediaType", "season", "episode", "title", "poster"]
        v = ProfilesStr(pref, k, "")
        if v = "" then v = ProfilesStr(fb, k, "")
        meta[k] = v
    end for
    if meta.mediaType = "" then meta.mediaType = "movie"
    return meta
end function

' ------------------------------------------------------------------
' Per-profile watchlist (lean: id + mediaType + timestamp only).
' store.watchlist: { "<profileId>": [ { id, m, t } ] } most-recent-first,
' cap 60 (2026-09-23: raised from 30 per user request; lean entries are
' ~35B, so 60 x 4 profiles stays well inside the registry budget).
' Membership always compares id + mediaType together: TMDB movie and TV id
' spaces are independent, so an id-only match (the old behavior) let a
' movie and a show sharing a number clobber each other.
' ------------------------------------------------------------------

function ProfilesWatchlistGet(store as Object, profileId as String) as Object
    if store = invalid or profileId = "" or profileId = invalid then return []
    wl = store.watchlist
    if wl = invalid then return []
    if not wl.DoesExist(profileId) then return []
    v = wl[profileId]
    if type(v) <> "roArray" then return []
    return v
end function

' True when the (id + mediaType) pair is in the profile's list.
function ProfilesWatchlistHas(store as Object, profileId as String, tmdbId as String, mediaType as String) as Boolean
    list = ProfilesWatchlistGet(store, profileId)
    for each e in list
        if e <> invalid and ProfilesStr(e, "id", "") = tmdbId and ProfilesStr(e, "m", "movie") = mediaType then
            return true
        end if
    end for
    return false
end function

sub ProfilesWatchlistAdd(store as Object, profileId as String, tmdbId as String, mediaType as String)
    if store = invalid or profileId = "" or profileId = invalid then return
    if tmdbId = "" then return
    if ProfilesFindIndex(store, profileId) < 0 then return
    if store.watchlist = invalid then store.watchlist = {}
    wl = store.watchlist
    if not wl.DoesExist(profileId) then wl[profileId] = []
    list = wl[profileId]
    if type(list) <> "roArray" then list = []
    if type(mediaType) <> "roString" and type(mediaType) <> "String" then mediaType = "movie"
    ' Dedupe on the full (id + mediaType) pair, then re-add at front.
    cleaned = []
    for each e in list
        if e = invalid or ProfilesStr(e, "id", "") <> tmdbId or ProfilesStr(e, "m", "movie") <> mediaType then
            cleaned.Push(e)
        end if
    end for
    cleaned.Unshift({ id: tmdbId, m: mediaType, t: ProfilesTimeNow() })
    while cleaned.count() > 60
        cleaned.Pop()
    end while
    wl[profileId] = cleaned
    ProfilesSave(store)
end sub

sub ProfilesWatchlistRemove(store as Object, profileId as String, tmdbId as String, mediaType as String)
    if store = invalid or profileId = "" or profileId = invalid then return
    list = ProfilesWatchlistGet(store, profileId)
    if list.count() = 0 then return
    cleaned = []
    for each e in list
        if e = invalid or ProfilesStr(e, "id", "") <> tmdbId or ProfilesStr(e, "m", "movie") <> mediaType then
            cleaned.Push(e)
        end if
    end for
    if cleaned.count() = list.count() then return
    store.watchlist[profileId] = cleaned
    ProfilesSave(store)
end sub

' Add or remove; returns true when the title is now in the watchlist.
function ProfilesWatchlistToggle(store as Object, profileId as String, rec as Object) as Boolean
    if store = invalid or profileId = "" or profileId = invalid then return false
    if rec = invalid then return false
    tmdbId = ProfilesStr(rec, "tmdbId", "")
    if tmdbId = "" then return false
    mediaType = ProfilesStr(rec, "mediaType", "movie")
    has = ProfilesWatchlistHas(store, profileId, tmdbId, mediaType)
    if has then
        ProfilesWatchlistRemove(store, profileId, tmdbId, mediaType)
        return false
    end if
    ProfilesWatchlistAdd(store, profileId, tmdbId, mediaType)
    return true
end function

' Resume points for a profile as [{key, rec}], newest-updated first.
function ProfilesResumeList(store as Object, profileId as String) as Object
    arr = []
    b = ProfilesGetBucket(store, profileId)
    if b = invalid then return arr
    for each k in b
        e = b[k]
        if type(e) = "roAssociativeArray" then
            arr.Push({ key: k, rec: e })
        end if
    end for
    n = arr.count()
    for i = 0 to n - 1
        for j = 0 to n - 2
            if ProfilesInt(arr[j].rec, "u", 0) < ProfilesInt(arr[j + 1].rec, "u", 0) then
                tmp = arr[j]
                arr[j] = arr[j + 1]
                arr[j + 1] = tmp
            end if
        end for
    end for
    return arr
end function

function ProfilesFormatTime(totalSec as Integer) as String
    t = totalSec
    if t = invalid or t < 0 then t = 0
    h = t \ 3600
    m = (t MOD 3600) \ 60
    s = t MOD 60
    ms = m.ToStr()
    ss = s.ToStr()
    if m < 10 then ms = "0" + m.ToStr()
    if s < 10 then ss = "0" + s.ToStr()
    if h > 0 then return h.ToStr() + ":" + ms + ":" + ss
    return m.ToStr() + ":" + ss
end function

' ------------------------------------------------------------------
' Profile avatars: procedural colored-initial tiles (zero new files,
' zero licensing risk). Stored as an "avatar" 0-3 color index on the
' profile record; old records without the field fall back to slot order.
' ------------------------------------------------------------------

function ProfilesAvatarHex(idx as Integer) as String
    pal = ["0xD42028FF", "0x2563EBFF", "0x059669FF", "0x7C3AEDFF"]
    n = pal.count()
    k = idx mod n
    if k < 0 then k = 0
    return pal[k]
end function

function ProfilesAvatarIndex(store as Object, id as String) as Integer
    i = ProfilesFindIndex(store, id)
    if i < 0 then return 0
    p = store.profiles[i]
    raw = ProfilesInt(p, "avatar", -1)
    if raw >= 0 then return raw mod 4
    return i mod 4
end function

function ProfilesAvatarInitial(name as String) as String
    if name = invalid or name = "" then return "?"
    ch = Left(name, 1)
    return UCase(ch)
end function

sub ProfilesCycleAvatar(store as Object, id as String)
    i = ProfilesFindIndex(store, id)
    if i < 0 then return
    cur = ProfilesAvatarIndex(store, id)
    store.profiles[i].avatar = (cur + 1) mod 4
    store.profiles[i].updated = ProfilesTimeNow()
    ProfilesSave(store)
end sub

' ------------------------------------------------------------------
' Real avatar art (DiceBear HTTP API, deterministic seed = profile id):
' avataaars + bottts by Pablo Stanley (free for personal and commercial
' use), lorelei remix CC0 1.0. PNG 256px loads directly in Poster nodes,
' zero bundled bytes. Stored as "avatarStyle" on the profile record; old
' records without the field fall back to the first style. The background
' color follows the existing avatar color index so every profile keeps its
' identity color; the procedural initial tile underneath stays as the
' offline fallback (Poster is transparent while loading / on failure).
' ------------------------------------------------------------------

function ProfilesAvatarStyles() as Object
    return ["avataaars", "bottts", "lorelei"]
end function

function ProfilesAvatarStyle(store as Object, id as String) as String
    styles = ProfilesAvatarStyles()
    i = ProfilesFindIndex(store, id)
    if i >= 0 then
        raw = ProfilesStr(store.profiles[i], "avatarStyle", "")
        for each s in styles
            if raw <> "" and raw = s then return raw
        end for
    end if
    return styles[0]
end function

function ProfilesAvatarBg(store as Object, id as String) as String
    hex = ProfilesAvatarHex(ProfilesAvatarIndex(store, id))
    if hex <> invalid and hex.Len() >= 8 then
        return Mid(hex, 3, 6)
    end if
    return "d42028"
end function

function ProfilesAvatarSeed(id as String) as String
    if id = invalid or id = "" then return "roku"
    seed = ""
    for i = 1 to id.Len()
        ch = Mid(id, i, 1)
        code = Asc(ch)
        if (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) then
            seed = seed + ch
        end if
        if seed.Len() >= 32 then exit for
    end for
    if seed = "" then seed = "roku"
    return seed
end function

function ProfilesAvatarUrl(store as Object, id as String) as String
    style = ProfilesAvatarStyle(store, id)
    bg = ProfilesAvatarBg(store, id)
    return "https://api.dicebear.com/9.x/" + style + "/png?seed=" + ProfilesAvatarSeed(id) + "&size=256&backgroundColor=" + bg
end function

sub ProfilesCycleAvatarStyle(store as Object, id as String)
    i = ProfilesFindIndex(store, id)
    if i < 0 then return
    styles = ProfilesAvatarStyles()
    cur = ProfilesAvatarStyle(store, id)
    nxt = styles[0]
    for k = 0 to styles.count() - 1
        if styles[k] = cur then
            nxt = styles[(k + 1) mod styles.count()]
            exit for
        end if
    end for
    store.profiles[i].avatarStyle = nxt
    store.profiles[i].updated = ProfilesTimeNow()
    ProfilesSave(store)
end sub
