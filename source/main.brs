sub Main(args as Object)
    screen = CreateObject("roSGScreen")
    m.port = CreateObject("roMessagePort")
    screen.setMessagePort(m.port)
    splash = screen.CreateScene("SplashScene")
    if args <> invalid then
        ' Deep-link keys arrive lowercase (contentid/mediatype); accept any case.
        ' https://developer.roku.com/dev/docs/implementing-deep-linking
        ' Stashed on the splash; forwarded to HomeScene on transition.
        cid = invalid
        if args.contentId <> invalid then cid = args.contentId
        if cid = invalid and args.contentid <> invalid then cid = args.contentid
        if cid <> invalid and cid.ToStr() <> "" then
            splash.launchArgs = args
        end if
    end if
    screen.show()

    ' Splash completion arrives as an roSGNodeEvent on this same port.
    ' (Custom Scene functions can only run on the render thread, so main
    ' never calls into the scene — it only observes this field.)
    splash.observeField("splashDone", m.port)

    home = invalid
    clock = CreateObject("roTimeSpan")
    failsafeMs = 12000

    while true
        msg = wait(2000, m.port)
        if msg = invalid then
            ' wait timeout: failsafe so a dead splash can never hang the app.
            if home = invalid and clock.TotalMilliseconds() > failsafeMs then
                ? "SPLASH failsafe timeout -> Home"
                home = GoHome(screen, splash)
            end if
        else if type(msg) = "roSGScreenEvent" then
            if msg.isScreenClosed() then
                exit while
            end if
        else if type(msg) = "roSGNodeEvent" then
            if msg.getField() = "splashDone" and msg.getData() = true and home = invalid then
                ? "SPLASH signal received -> Home"
                home = GoHome(screen, splash)
            end if
        else if type(msg) = "roInputEvent" and msg.isInput() then
            ' Warm deep link while running (supports_input_launch=1).
            ' https://developer.roku.com/dev/docs/implementing-deep-linking
            info = msg.GetInfo()
            if info <> invalid then
                target = home
                if target = invalid then target = splash
                if info.DoesExist("contentid") then
                    target.launchArgs = info
                else if info.DoesExist("contentId") then
                    target.launchArgs = info
                end if
            end if
        end if
    end while
end sub

' Swap to the home scene. screen.CreateScene replaces the current scene —
' a Scene node must never be appended as a child of another Scene.
' Rendezvous fix: splash.launchArgs MUST be read BEFORE CreateScene("HomeScene")
' — creating the new scene destroys SplashScene, and a field read on the dead
' node aborts the rendezvous ("Rendezvous aborted for SplashScene" at the old
' main.brs(66)) and silently drops the deep-link args.
function GoHome(screen as Object, splash as Object) as Object
    la = invalid
    if splash <> invalid and splash.launchArgs <> invalid then
        la = splash.launchArgs
    end if
    h = screen.CreateScene("HomeScene")
    if la <> invalid then
        h.launchArgs = la
    end if
    screen.show()
    ? "HOME scene created"
    return h
end function
