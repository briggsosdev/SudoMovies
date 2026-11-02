' Parses a Server-Sent-Events body (as returned by the providers-api /scrape endpoint)
' and returns the JSON payload of the "completed" event, or invalid if not found.
function ParseSseCompleted(body as String) as Dynamic
    if body = invalid or body = "" then
        return invalid
    end if

    normalized = body.Replace(Chr(13), "")
    blocks = normalized.Split(Chr(10) + Chr(10))
    for each block in blocks
        lower = LCase(block)
        if lower.Instr("event: completed") >= 0 or lower.Instr("event:completed") >= 0 then
            lines = block.Split(Chr(10))
            dataLines = []
            for each line in lines
                trimLine = line.Trim()
                if Left(trimLine, 5) = "data:" then
                    ' Method Mid() is zero-based: payload starts at index 5;
                    ' Trim() absorbs the optional space after the colon.
                    ' https://developer.roku.com/dev/docs/ifstringops
                    payload = trimLine.Mid(5).Trim()
                    if payload <> "[DONE]" then
                        dataLines.Push(payload)
                    end if
                end if
            end for
            joined = ""
            for each part in dataLines
                if joined <> "" then
                    joined = joined + Chr(10)
                end if
                joined = joined + part
            end for
            if joined <> "" then
                return JsonParseSafe(joined)
            end if
        end if
    end for
    return invalid
end function

' Extracts useful progress text from intermediate SSE events (human readable).
function ParseSseLastProgress(body as String) as String
    if body = invalid or body = "" then
        return ""
    end if
    normalized = body.Replace(Chr(13), "")
    blocks = normalized.Split(Chr(10) + Chr(10))
    progressFor = ["discoverEmbeds", "source"]
    result = ""
    for each block in blocks
        lower = LCase(block)
        for each evtName in progressFor
            if lower.Instr("event: " + evtName) >= 0 then
                lines = block.Split(Chr(10))
                for each line in lines
                    trimLine = line.Trim()
                    if Left(trimLine, 5) = "data:" and trimLine.Mid(5).Trim() <> "[DONE]" then
                        data = JsonParseSafe(trimLine.Mid(5).Trim())
                        if data <> invalid then
                            if data.embedCount <> invalid then
                                result = "Found " + data.embedCount.ToStr() + " embeds..."
                            end if
                        end if
                    end if
                end for
            end if
        end for
    end for
    return result
end function