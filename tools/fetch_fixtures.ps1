$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$fx = Join-Path $root "tests\fixtures"
if (-not (Test-Path $fx)) { New-Item -ItemType Directory -Path $fx -Force | Out-Null }

$ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"

function Get-Raw($url) {
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("User-Agent", $ua)
    return $wc.DownloadData($url)
}

# Stars are stored gzipped. tests/ sits outside components/, so it is not
# packaged into the shipped channel, but gzipping still keeps the repo lean
# (~10:1). The test runner gunzips them into a temp dir before invoking brs.
function Save-Gz($bytes, $dest) {
    $ms = New-Object System.IO.MemoryStream
    $gz = New-Object System.IO.Compression.GZipStream($ms, [System.IO.Compression.CompressionMode]::Compress)
    $gz.Write($bytes, 0, $bytes.Length)
    $gz.Close()
    [System.IO.File]::WriteAllBytes($dest, $ms.ToArray())
    Write-Output ("  {0,-26} {1,8:N0} bytes gz" -f (Split-Path -Leaf $dest), (Get-Item $dest).Length)
}

Write-Output "fetching fixtures into $fx"

$raw = Get-Raw "https://reanime.to/home"
Save-Gz $raw (Join-Path $fx "reanime.html.gz")

# Entity-encoded twin so the parser's glyph-independence stays covered.
$starBytes = [byte[]](0xE2, 0x98, 0x85)
$replacement = [System.Text.Encoding]::ASCII.GetBytes("&#9733;")
$out = New-Object System.Collections.ArrayList
for ($i = 0; $i -lt $raw.Length; $i++) {
    $isStar = ($i -lt $raw.Length - 2 -and $raw[$i] -eq 0xE2 -and $raw[$i + 1] -eq 0x98 -and $raw[$i + 2] -eq 0x85)
    if ($isStar) {
        foreach ($c in $replacement) { [void]$out.Add($c) }
        $i = $i + 2
    }
    else { [void]$out.Add($raw[$i]) }
}
Save-Gz $out.ToArray() (Join-Path $fx "reanime_entity.html.gz")

Save-Gz (Get-Raw "https://ok.ru/videoembed/15937498778353") (Join-Path $fx "ok_embed.html.gz")
Save-Gz (Get-Raw "https://vidmoly.org/embed-gmucjmfc3qhe.html") (Join-Path $fx "vidmoly_embed.html.gz")

# Drop any previously-committed uncompressed copies.
Get-ChildItem $fx -Filter "*.html" -ErrorAction SilentlyContinue | Remove-Item -Force

Write-Output ""
Write-Output "now run: npm test"