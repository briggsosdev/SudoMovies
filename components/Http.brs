' Synchronous-style HTTP GET helper. Meant to run inside a Task thread.
' Uses the async roUrlEvent API so status codes work reliably.
' Returns { status: Integer (0 on transport failure/timeout), body: String }
function HttpGetText(url as String, headers as Object) as Object
    ut = CreateObject("roUrlTransfer")
    ' Standard Roku CA bundle (audit finding): without it, HTTPS hosts whose
    ' chain is not in the firmware default trust store fail as generic
    ' status-0 "unreachable" errors.
    ut.SetCertificatesFile("common:/certs/ca-bundle.crt")
    ut.SetUrl(url)
    if headers <> invalid and headers.count() > 0 then
        ut.SetHeaders(headers)
    end if
    port = CreateObject("roMessagePort")
    ut.SetMessagePort(port)
    started = ut.AsyncGetToString()
    ? "HTTP async started=" + started.ToStr() + " url=" + url
    if not started then
        return {
            status: 0,
            body: ""
        }
    end if
    event = wait(15000, port)
    if event = invalid then
        ? "HTTP timeout url=" + url
        ut.AsyncCancel()
        return {
            status: 0,
            body: ""
        }
    end if
    et = type(event)
    if et = "roUrlEvent" then
        evInt = event.getInt()
        evCode = event.getResponseCode()
        evFail = event.getFailureReason()
        evLen = event.getString().Len()
        failStr = ""
        if evFail <> invalid then failStr = evFail.ToStr()
        ? "HTTP event int=" + evInt.ToStr() + " code=" + evCode.ToStr() + " fail=" + failStr + " len=" + evLen.ToStr() + " url=" + url
        if evInt = 1 then
            return {
                status: evCode,
                body: event.getString()
            }
        end if
    else
        ? "HTTP unexpected event type=" + et + " url=" + url
    end if
    return {
        status: 0,
        body: ""
    }
end function

' Builds a headers AA that only contains string values (safe for SetHeaders).
function HeadersFromAA(input as Object) as Object
    result = {}
    if input = invalid then
        return result
    end if
    for each k in input.Keys()
        v = input[k]
        if type(v) = "roString" or type(v) = "String" then
            result[k] = v
        else if v <> invalid then
            result[k] = v.ToStr()
        end if
    end for
    return result
end function