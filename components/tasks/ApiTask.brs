sub init()
    m.top.functionName = "RunApiTask"
end sub

sub RunApiTask()
    ' try/catch so a transport error can never strand the task at control="run"
    ' with no status/raw event (would leave HomeScene flags stuck).
    try
        headers = m.top.headers
        if headers = invalid then
            headers = {}
        end if
        result = HttpGetText(m.top.url, headers)
        m.top.status = result.status
        m.top.raw = result.body
    catch e
        m.top.status = 0
        m.top.raw = ""
    end try
    m.top.control = "stop"
end sub