' Video splash (splashmov.mkv) with guaranteed handoff to Home.
'
' Architecture (see source/main.brs): this Scene NEVER touches HomeScene
' directly — a Scene node cannot be appended inside another Scene, and a
' main-thread caller cannot invoke this component's functions except via
' callFunc. Instead this component only signals completion by setting its
' splashDone interface field; main.brs observes that field and swaps scenes
' with screen.CreateScene("HomeScene").
'
' Three independent paths all lead to finish(): video finished, video
' error, and a 5s timer. finish() is idempotent (m.done guard).
sub init()
    ? "SPLASH init"
    m.top.backgroundURI = ""
    m.done = false

    m.video = m.top.findNode("splashVideo")
    content = createObject("roSGNode", "ContentNode")
    content.url = "pkg:/images/splashmov.mkv"
    content.streamFormat = "mkv"
    m.video.content = content
    m.video.observeField("state", "onVideoState")

    m.timer = m.top.findNode("splashTimer")
    m.timer.observeField("fire", "onSplashDone")
    m.timer.control = "start"

    m.video.control = "play"
end sub

sub onVideoState()
    st = m.video.state
    ? "SPLASH video state=" + st
    if st = "finished" or st = "error" then
        finish()
    end if
end sub

sub onSplashDone()
    ? "SPLASH timer fired"
    finish()
end sub

sub finish()
    if m.done = true then
        return
    end if
    m.done = true
    ? "SPLASH done -> signaling main"
    try
        m.video.control = "stop"
    catch e1
    end try
    try
        m.timer.control = "stop"
    catch e2
    end try
    m.top.splashDone = true
end sub
