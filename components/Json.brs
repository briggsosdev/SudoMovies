' ACTUALLY safe: a non-string input returns invalid instead of throwing at
' the typed-parameter boundary (ParseJson(jsonString as String) with a
' non-string argument raises a runtime error - the documented pre-2026-09-19
' error-99 path), and a ParseJson failure of any kind degrades to invalid so
' every caller treats it as a cache/parse miss instead of an exception.
function JsonParseSafe(value as Dynamic) as Dynamic
    if value = invalid then
        return invalid
    end if
    if type(value) <> "String" and type(value) <> "roString" then
        return invalid
    end if
    if value = "" then
        return invalid
    end if
    try
        return ParseJson(value)
    catch e
        return invalid
    end try
end function

function JsonClone(value as Dynamic) as Dynamic
    if value = invalid then
        return invalid
    end if
    return ParseJson(FormatJson(value))
end function