function ConfigDefaults() as Object
    return {
        tmdbKey: AppConstants().tmdbDefaultKey,
        febboxToken: "",
        febboxTokens: [],
        providerApiBase: "",
        urbanApiBase: "https://brokensilenze.mom"
    }
end function

' Rotate to the next saved Febbox token when the active one hits its quota limit.
' Returns the active token, or "" if none are left.
function FebboxGetActiveToken(cfg as Object) as String
    if cfg <> invalid and cfg.febboxToken <> "" then
        return cfg.febboxToken
    end if
    if cfg <> invalid and cfg.febboxTokens <> invalid and cfg.febboxTokens.count() > 0 then
        return cfg.febboxTokens[0]
    end if
    if cfg <> invalid then
        return cfg.febboxToken
    end if
    return ""
end function

' Advance to the next saved Febbox token and make it active.
' Returns the new active token, or "" if the current one is already the last.
function FebboxRotateToken(cfg as Object) as String
    tokens = cfg.febboxTokens
    if tokens = invalid or tokens.count() = 0 then
        return ""
    end if
    if cfg.febboxToken = "" then
        return ""
    end if
    for i = 0 to tokens.count() - 1
        if tokens[i] = cfg.febboxToken then
            nextIdx = i + 1
            if nextIdx < tokens.count() then
                cfg.febboxToken = tokens[nextIdx]
                return cfg.febboxToken
            else
                return ""
            end if
        end if
    end for
    return ""
end function

function ConfigSave(cfg as Object)
    PersistEnqueue("settings", "config", FormatJson(cfg))
end function

' Last-chosen stream source (provider|quality) remembered per channel.
function ConfigGetLastSource() as String
    return PersistReadRaw("settings", "lastSource")
end function

sub ConfigSetLastSource(key as String)
    PersistEnqueue("settings", "lastSource", key)
end sub

' Stable per-candidate key (provider|quality) used to remember the user's last
' chosen source. Provider comes from the first word of the picker label.
function SourceKey(cand as Object) as String
    label = SafeStr(cand, "label", "")
    provider = ""
    if label <> "" then
        sp = Instr(1, label, " ")
        if sp > 1 then
            provider = Left(label, sp - 1)
        else
            provider = label
        end if
    end if
    if provider = "" then provider = "SRC"
    q = SafeStr(cand, "quality", "")
    if q = "" then q = "?"
    return provider + "|" + q
end function

function ConfigLoad() as Object
    defaults = ConfigDefaults()
    cfg = {
        tmdbKey: defaults.tmdbKey,
        febboxToken: defaults.febboxToken,
        febboxTokens: defaults.febboxTokens,
        providerApiBase: defaults.providerApiBase
    }
    raw = PersistReadRaw("settings", "config")
    if raw <> "" then
        parsed = JsonParseSafe(raw)
        if parsed <> invalid and type(parsed) = "roAssociativeArray" then
            for each k in parsed
                if parsed[k] <> invalid then
                    cfg[k] = parsed[k]
                end if
            end for
        end if
    end if
    ' In the release build there is no bundled working token, so never
    ' overwrite a token the user has saved in the registry.
    if defaults.febboxToken <> "" then
        cfg.febboxToken = defaults.febboxToken
    end if
    ' Merge any user-saved tokens into the rotation list, keeping the
    ' active token first and de-duplicating. Never inject an empty default.
    merged = []
    seen = {}
    if cfg.febboxToken <> "" and not seen.DoesExist(cfg.febboxToken) then
        merged.Push(cfg.febboxToken)
        seen[cfg.febboxToken] = true
    end if
    for each t in cfg.febboxTokens
        if t <> invalid and t <> "" and not seen.DoesExist(t) then
            merged.Push(t)
            seen[t] = true
        end if
    end for
    if defaults.febboxToken <> "" and not seen.DoesExist(defaults.febboxToken) then
        merged.Unshift(defaults.febboxToken)
    end if
    cfg.febboxTokens = merged
    return cfg
end function

' Configured = at least one stream backend is available (Febbox token or a provider API).
function ConfigIsConfigured(cfg as Object) as Boolean
    if cfg = invalid then
        return false
    end if
    return cfg.febboxToken <> "" or cfg.providerApiBase <> ""
end function