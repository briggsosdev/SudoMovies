// SudoMovies — Samsung Tizen scaffold.
// NOTE: This is a skeleton. The BrightScript channel (Roku) cannot run on Tizen.
// Porting the full TMDB/Febbox/VixSrc pipeline requires reimplementing it in JS.
// Configure your TMDB key + backend URL below.

const CONFIG = {
    tmdbKey: "YOUR_TMDB_KEY_HERE",
    // Optional: point at a pmor-style backend instead of calling TMDB directly.
    backendUrl: "",
};

const TMDB = "https://api.themoviedb.org/3";
const IMG = "https://image.tmdb.org/t/p/w342";

const statusEl = document.getElementById("status");
const rowsEl = document.getElementById("rows");
const playerWrap = document.getElementById("playerWrap");
const player = document.getElementById("player");
const backBtn = document.getElementById("backBtn");

function setStatus(t) { statusEl.textContent = t; }

async function tmdb(path) {
    const url = `${TMDB}${path}${path.includes("?") ? "&" : "?"}api_key=${CONFIG.tmdbKey}`;
    const r = await fetch(url);
    if (!r.ok) throw new Error("TMDB " + r.status);
    return r.json();
}

function makeTile(item) {
    const div = document.createElement("div");
    div.className = "tile";
    const img = document.createElement("img");
    img.src = item.poster_path ? IMG + item.poster_path : "";
    img.alt = item.title || item.name || "";
    const t = document.createElement("div");
    t.className = "title";
    t.textContent = item.title || item.name || "";
    div.appendChild(img);
    div.appendChild(t);
    div.addEventListener("click", () => openPlayer(item));
    return div;
}

function renderRow(title, items) {
    const row = document.createElement("div");
    row.className = "row";
    const h = document.createElement("h2");
    h.textContent = title;
    row.appendChild(h);
    const tiles = document.createElement("div");
    tiles.className = "tiles";
    (items || []).forEach(i => tiles.appendChild(makeTile(i)));
    row.appendChild(tiles);
    rowsEl.appendChild(row);
}

async function loadHome() {
    setStatus("Loading home…");
    try {
        const popular = await tmdb("/movie/popular");
        const top = await tmdb("/movie/top_rated");
        rowsEl.innerHTML = "";
        renderRow("Popular Movies", popular.results);
        renderRow("Top Rated", top.results);
        setStatus("Ready");
    } catch (e) {
        setStatus("Error: " + e.message);
    }
}

function openPlayer(item) {
    // Playback requires a stream URL. This scaffold has no resolver wired up.
    // Wire your backend (e.g. a pmor server) or a direct stream URL here.
    setStatus("No stream resolver wired up yet for: " + (item.title || item.name));
}

backBtn.addEventListener("click", () => {
    player.pause();
    player.src = "";
    playerWrap.classList.add("hidden");
});

// Tizen remote key handling (basic)
document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" || e.key === "Backspace") {
        if (!playerWrap.classList.contains("hidden")) {
            backBtn.click();
        }
    }
});

loadHome();
