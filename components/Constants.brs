function AppConstants() as Object
    return {
        appName: "SudoMovies",
        version: "1.1",
        tmdbBase: "https://api.themoviedb.org/3",
        tmdbImageBase: "https://image.tmdb.org/t/p",
        tmdbDefaultKey: "",
        femboxBase: "https://fembox.aether.cx",
        scrapePath: "/scrape",
        embedPath: "/scrape/embed",
        maxEmbedsToResolve: 4,
        searchResultsLimit: 40,
        homeRows: [
            { id: "trending/movie/day",  title: "Trending Today" },
            { id: "movie/now_playing",   title: "Now Playing" },
            { id: "movie/popular",       title: "Popular Movies" },
            { id: "movie/top_rated",     title: "Top Rated" },
            { id: "movie/upcoming",      title: "Coming Soon" },
            { id: "trending/tv/week",    title: "TV Shows", isTv: true },
            { id: "trending/movie/week", title: "Trending This Week" },
            { id: "tv/popular",          title: "Popular TV Shows", isTv: true },
            { id: "tv/top_rated",        title: "Top Rated TV", isTv: true },
            { id: "discover/movie?with_genres=28", title: "Action & Adventure" },
            { id: "discover/movie?with_genres=35", title: "Comedies" }
        ]
    }
end function

function UrlEncode(value as String) as String
    ut = CreateObject("roUrlTransfer")
    return ut.Escape(value)
end function