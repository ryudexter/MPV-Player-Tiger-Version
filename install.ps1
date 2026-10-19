<#
Installs MPV Player: Tiger Version (this mpv setup) on Windows 10 or 11, or
fills in whatever is missing from an existing install. Safe to run again: it
moves aside anything it has to replace, and an update keeps your saved
positions and settings.

  irm https://raw.githubusercontent.com/ryudexter/MPV-Player-Tiger-Version/main/install.ps1 | iex

or from a clone:   powershell -ExecutionPolicy Bypass -File install.ps1

Options (through irm, pass them like this):
  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/ryudexter/MPV-Player-Tiger-Version/main/install.ps1))) -NoDeps

  -NoDeps          install nothing else: use the mpv already on this PC
  -NoAssociations  don't add mpv to "Open with", the folder menu or the Start menu
  -MpvPath <exe>   use this mpv.exe
  -Uninstall       take the "Open with" entries, the folder menu item and the
                   Start menu shortcut out again (your config folder stays)

What it does, all of it per-user - nothing needs an administrator:
  1. mpv: the official Windows build from github.com/mpv-player/mpv, into
     %LOCALAPPDATA%\Programs\mpv, unless an mpv 0.39 or newer is already here.
  2. yt-dlp.exe next to the config, so YouTube links play. With winget, also
     ffmpeg, Python, and through pipx subliminal and ffsubsync (the b and
     Alt+b keys). Any of these failing only costs that one feature.
  3. This setup in %APPDATA%\mpv (or an mpv's portable_config, if it has one).
     A config that was already there moves to mpv.backup-<date>.
  4. mpv-open.exe, compiled from windows\mpv-open.cs with Windows' own C#
     compiler: the single-window launcher, and the Explorer / Recycle Bin /
     battery helper the scripts use.
  5. "mpv (Tiger Version)" under Open with for video, audio and playlist files,
     "Play with mpv (Tiger Version)" on folders, and a Start menu shortcut.
     Windows does not let an installer make itself the default; the last lines
     say how to do it in two clicks.

MPV_SETUP_SOURCE (a folder or a .zip) overrides where the setup comes from,
for testing.
#>
[CmdletBinding()]
param(
    [switch]$NoDeps,
    [switch]$NoAssociations,
    [string]$MpvPath,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'      # Windows PowerShell's progress bar makes downloads crawl
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$Repo     = 'ryudexter/MPV-Player-Tiger-Version'
$RepoGit  = "https://github.com/$Repo.git"
$RepoZip  = "https://github.com/$Repo/archive/refs/heads/main.zip"
$AppName  = 'mpv (Tiger Version)'
$ProgId   = 'MPVTiger.File'
$MinMpv   = [version]'0.39'
$Stamp    = Get-Date -Format 'yyyyMMdd-HHmmss'
$LocalMpv = Join-Path $env:LOCALAPPDATA 'Programs\mpv'
$Shortcut = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\$AppName.lnk"

# What "Open with" offers it for: the same kinds of file mpv.app claims on a Mac.
$Video    = '.mkv .mp4 .m4v .mov .avi .webm .wmv .flv .mpg .mpeg .m2v .ts .m2ts .mts .3gp .3g2 .ogv' -split ' '
$Audio    = '.mp3 .m4a .aac .flac .wav .aif .aiff .ogg .opus' -split ' '
$Playlist = '.m3u .m3u8 .pls' -split ' '
$Types    = $Video + $Audio + $Playlist

function Say($m)  { Write-Host ''; Write-Host "==> $m" -ForegroundColor Cyan }
function Note($m) { Write-Host "    $m" }
function Warn($m) { Write-Host "    ! $m" -ForegroundColor Yellow }
# throw, not exit: under `irm | iex` an exit would close the user's PowerShell
# window along with the installer.
function Die($m)  { throw $m }

# Runs a program and returns its output. Windows PowerShell 5.1 turns a native
# program's stderr into errors, which $ErrorActionPreference = 'Stop' would make
# fatal, so it is relaxed for the call. $LASTEXITCODE says how it went.
function Run($exe) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { return (& $exe @args 2>&1 | ForEach-Object { "$_" }) }
    finally { $ErrorActionPreference = $old }
}

if ($env:OS -ne 'Windows_NT') { Die 'This is the Windows installer. On macOS and Linux run install.sh.' }

# ---- uninstall -------------------------------------------------------------------

function Remove-Associations {
    $classes = 'HKCU:\Software\Classes'
    foreach ($ext in $Types) {
        $k = "$classes\$ext\OpenWithProgids"
        if (Test-Path $k) { Remove-ItemProperty -Path $k -Name $ProgId -ErrorAction SilentlyContinue }
    }
    foreach ($k in "$classes\$ProgId", "$classes\Applications\mpv-open.exe",
                   "$classes\Directory\shell\MPVTiger", 'HKCU:\Software\MPVTiger') {
        if (Test-Path $k) { Remove-Item -Path $k -Recurse -Force }
    }
    Remove-ItemProperty -Path 'HKCU:\Software\RegisteredApplications' -Name $AppName -ErrorAction SilentlyContinue
    if (Test-Path $Shortcut) { Remove-Item $Shortcut -Force }
}

function Send-AssocChanged {
    if (-not ('Tiger.Shell' -as [type])) {
        Add-Type -Namespace Tiger -Name Shell -MemberDefinition @'
[DllImport("shell32.dll")] public static extern void SHChangeNotify(int e, uint f, System.IntPtr a, System.IntPtr b);
'@
    }
    [Tiger.Shell]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)   # SHCNE_ASSOCCHANGED
}

if ($Uninstall) {
    Say "Removing $AppName from Open with, the folder menu and the Start menu"
    Remove-Associations
    Send-AssocChanged
    Note 'Done. The config folder and mpv itself are left where they are:'
    Note "  $env:APPDATA\mpv   and   $LocalMpv"
    return
}

# ---- 1. mpv --------------------------------------------------------------------------

function Get-MpvVersion($exe) {
    # mpv.com is the console twin of mpv.exe; it prints where mpv.exe would not wait
    $com = [IO.Path]::ChangeExtension($exe, '.com')
    $run = $exe
    if (Test-Path $com) { $run = $com }
    try {
        $out = Run $run --no-config --version | Select-Object -First 1
        if ($out -match 'mpv v?(\d+\.\d+(\.\d+)?)') { return [version]$Matches[1] }
    } catch { }
    return $null
}

function Find-Mpv {
    if ($MpvPath) {
        if (-not (Test-Path $MpvPath)) { Die "No mpv at $MpvPath" }
        return (Resolve-Path $MpvPath).Path
    }
    $mine = Join-Path $LocalMpv 'mpv.exe'
    if (Test-Path $mine) { return $mine }
    $cmd = Get-Command mpv.exe -ErrorAction SilentlyContinue
    if ($cmd) {
        $p = $cmd.Source
        # Scoop puts a shim on PATH; the real mpv.exe is in its app folder
        if ($p -match '\\scoop\\shims\\') {
            $real = Join-Path (Split-Path (Split-Path $p)) 'apps\mpv\current\mpv.exe'
            if (Test-Path $real) { return $real }
        }
        return $p
    }
    return $null
}

# The newest release's tag. github.com/<repo>/releases/latest redirects to it,
# and unlike GitHub's API that page has no 60-requests-an-hour limit per
# address - which a shared or office connection can use up (the CI runners
# did). The API is only the fallback.
function Get-LatestTag($repo) {
    try {
        $r = Invoke-WebRequest "https://github.com/$repo/releases/latest" -Method Head -UseBasicParsing
        $u = $null
        if ($r.BaseResponse.ResponseUri) { $u = $r.BaseResponse.ResponseUri.AbsoluteUri }                 # Windows PowerShell
        elseif ($r.BaseResponse.RequestMessage) { $u = $r.BaseResponse.RequestMessage.RequestUri.AbsoluteUri } # PowerShell 7
        if ($u -match '/releases/tag/([^/?#]+)') { return $Matches[1] }
    } catch { }
    return (Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest" -Headers @{ 'User-Agent' = 'tiger-install' }).tag_name
}

function Install-Mpv {
    $arch = 'x86_64'
    if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { $arch = 'aarch64' }
    $tag = Get-LatestTag 'mpv-player/mpv'
    # mpv's own naming, e.g. v0.41.0/mpv-v0.41.0-x86_64-pc-windows-msvc.zip
    $name = "mpv-$tag-$arch-pc-windows-msvc.zip"
    Note "Downloading $name"
    $tmp = Join-Path $env:TEMP "tiger-mpv-$Stamp"
    New-Item -ItemType Directory -Force $tmp | Out-Null
    $zip = Join-Path $tmp 'mpv.zip'
    try {
        Invoke-WebRequest "https://github.com/mpv-player/mpv/releases/download/$tag/$name" -OutFile $zip -UseBasicParsing
    } catch { Die "Could not download $name from mpv's latest release ($tag): $($_.Exception.Message)" }
    Expand-Archive $zip -DestinationPath (Join-Path $tmp 'mpv') -Force
    Remove-Item (Join-Path $tmp 'mpv\*.pdb') -ErrorAction SilentlyContinue    # 200+ MB of debug symbols
    New-Item -ItemType Directory -Force $LocalMpv | Out-Null
    Copy-Item (Join-Path $tmp 'mpv\*') $LocalMpv -Recurse -Force
    Remove-Item $tmp -Recurse -Force
    # On the user's PATH, so `mpv` works in a terminal, as Homebrew's does on a Mac
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $userPath) { $userPath = '' }
    if (($userPath -split ';') -notcontains $LocalMpv) {
        [Environment]::SetEnvironmentVariable('Path', ($userPath.TrimEnd(';') + ';' + $LocalMpv).TrimStart(';'), 'User')
        $env:Path = $env:Path + ';' + $LocalMpv
        Note "Added $LocalMpv to your PATH"
    }
    return (Join-Path $LocalMpv 'mpv.exe')
}

if (Get-Process mpv -ErrorAction SilentlyContinue) {
    Die 'mpv is running. Quit it first (q in the player), then run this again.'
}

Say 'Looking for mpv'
$mpv = Find-Mpv
$ver = $null
if ($mpv) { $ver = Get-MpvVersion $mpv }
if ($mpv -and $ver -and $ver -ge $MinMpv) {
    Note "mpv $ver at $mpv"
} elseif ($NoDeps) {
    if (-not $mpv) { Die 'No mpv found, and -NoDeps says not to install one. Pass -MpvPath, or drop -NoDeps.' }
    if ($ver) { Warn "mpv $ver at $mpv is older than $MinMpv; parts of this setup need $MinMpv or newer." }
    else { Warn "Could not tell which mpv $mpv is; this setup needs $MinMpv or newer." }
} else {
    if ($mpv) { Note "mpv $ver at $mpv is older than $MinMpv - installing a current one beside it" }
    $mpv = Install-Mpv
    $ver = Get-MpvVersion $mpv
    Note "mpv $ver at $mpv"
}
$mpvDir = Split-Path $mpv

# mpv uses a portable_config folder beside mpv.exe INSTEAD of %APPDATA%\mpv when
# there is one - Scoop's mpv always has one - so the setup has to go there.
$Conf = Join-Path $env:APPDATA 'mpv'
if (Test-Path (Join-Path $mpvDir 'portable_config')) {
    $Conf = Join-Path $mpvDir 'portable_config'
    Note "This mpv reads its settings from $Conf, so the setup goes there"
}

# ---- 2. the config itself -------------------------------------------------------------

Say "Putting the setup in $Conf"
$git = Get-Command git.exe -ErrorAction SilentlyContinue
$isOurs = (Test-Path (Join-Path $Conf 'scripts\shuffle-mode.lua')) -and (Test-Path (Join-Path $Conf 'field-guide.html'))
$isClone = Test-Path (Join-Path $Conf '.git')

# Plain files only, and no .git. The Mac-only app/mpv-player.app is two
# symlinks into Homebrew that point nowhere on Windows, and Copy-Item gives up
# on the whole copy at the first of them.
function Copy-Tree($from, $to) {
    $from = (Resolve-Path $from).Path.TrimEnd('\')
    Get-ChildItem -LiteralPath $from -Recurse -Force -File |
        Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } |
        ForEach-Object {
            $rel = $_.FullName.Substring($from.Length + 1)
            if ($rel -match '^\.git(\\|$)') { return }
            $dst = Join-Path $to $rel
            New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
            Copy-Item -LiteralPath $_.FullName -Destination $dst -Force
        }
}

function Get-Setup($dest) {
    $src = $env:MPV_SETUP_SOURCE
    if ($src -and (Test-Path $src -PathType Container)) {
        Copy-Tree $src $dest
        return
    }
    if (-not $src -and $git) {
        $out = Run $git.Source clone --quiet $RepoGit $dest
        if ($LASTEXITCODE -ne 0) { Die "git clone failed: $out" }
        return
    }
    $tmp = Join-Path $env:TEMP "tiger-setup-$Stamp"
    New-Item -ItemType Directory -Force $tmp | Out-Null
    $zip = $src
    if (-not $zip) {
        $zip = Join-Path $tmp 'setup.zip'
        Invoke-WebRequest $RepoZip -OutFile $zip -UseBasicParsing
    }
    Expand-Archive $zip -DestinationPath $tmp -Force
    $top = Get-ChildItem $tmp -Directory | Select-Object -First 1
    Copy-Tree $top.FullName $dest
    Remove-Item $tmp -Recurse -Force
}

if ($isOurs -and $isClone -and $git -and -not $env:MPV_SETUP_SOURCE) {
    Run $git.Source -C $Conf pull --ff-only --quiet | Out-Null
    if ($LASTEXITCODE -eq 0) { Note 'Updated with git pull' }
    else { Warn "git pull did not go through - local changes? Left as it is: git -C `"$Conf`" status" }
} else {
    # Fetched next to it first, so a failed download leaves the old config in place.
    $new = "$Conf.installing-$Stamp"
    New-Item -ItemType Directory -Force $new | Out-Null
    Get-Setup $new
    if (Test-Path $Conf) {
        $backup = "$Conf.backup-$Stamp"
        Move-Item $Conf $backup
        if ($isOurs) { Note "The previous version is at $backup (in case you had edited it)" }
        else { Note "Your previous mpv config is now at $backup" }
        # What lives in the config folder but is not config: saved positions
        # (mpv kept them here before 0.38), subtitles fetched for read-only folders.
        foreach ($keep in 'watch_later', 'subs-fetched') {
            if (Test-Path (Join-Path $backup $keep)) {
                Copy-Item (Join-Path $backup $keep) $new -Recurse -Force
                Note "Kept $keep"
            }
        }
    }
    Move-Item $new $Conf
}

# ~~state, where the scripts keep the volume and mpv keeps resume positions
New-Item -ItemType Directory -Force (Join-Path $env:LOCALAPPDATA 'mpv') | Out-Null

# ---- 3. yt-dlp, ffmpeg, subliminal, ffsubsync ------------------------------------------

if (-not $NoDeps) {
    Say 'Installing the tools the scripts use'
    # yt-dlp beside the config: mpv's YouTube hook looks there first, whichever
    # mpv this is, and it updates itself with  yt-dlp -U
    $ytdlp = Join-Path $Conf 'yt-dlp.exe'
    if ((Test-Path $ytdlp) -or (Get-Command yt-dlp.exe -ErrorAction SilentlyContinue)) {
        Note 'yt-dlp: already installed'
    } else {
        $name = 'yt-dlp.exe'
        if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { $name = 'yt-dlp_arm64.exe' }
        try {
            Invoke-WebRequest "https://github.com/yt-dlp/yt-dlp/releases/latest/download/$name" -OutFile $ytdlp -UseBasicParsing
            Note 'yt-dlp: installed'
        } catch { Warn "yt-dlp didn't download: YouTube links won't play ($($_.Exception.Message))" }
    }

    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    function Refresh-Path {
        $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
    }
    function Winget-Install($id, $what) {
        Run $winget.Source install --id $id --exact --silent --scope user --source winget `
            --accept-package-agreements --accept-source-agreements --disable-interactivity | Out-Null
        if ($LASTEXITCODE -ne 0) {
            # some packages have no per-user installer; let winget pick
            Run $winget.Source install --id $id --exact --silent --source winget `
                --accept-package-agreements --accept-source-agreements --disable-interactivity | Out-Null
        }
        Refresh-Path
        if ($LASTEXITCODE -eq 0) { Note "$($what): installed" } else { Warn "$what didn't install (winget $id)" }
    }
    # The Store's python.exe stub in WindowsApps only opens the Store
    function Find-Python {
        $py = Get-Command py.exe -ErrorAction SilentlyContinue
        if ($py) { return @($py.Source, '-3') }
        $p = Get-Command python.exe -ErrorAction SilentlyContinue
        if ($p -and $p.Source -notlike '*\WindowsApps\*') { return @($p.Source) }
        # python.org's installer leaves python.exe off PATH unless asked
        $p = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python3*\python.exe') -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending | Select-Object -First 1
        if ($p) { return @($p.FullName) }
        return $null
    }

    if (Get-Command ffmpeg.exe -ErrorAction SilentlyContinue) { Note 'ffmpeg: already installed' }
    elseif ($winget) { Winget-Install 'Gyan.FFmpeg' 'ffmpeg' }
    else { Warn 'No winget, so no ffmpeg: Alt+b (re-time subtitles) needs it on PATH' }

    $python = Find-Python
    if (-not $python -and $winget) { Winget-Install 'Python.Python.3.13' 'Python'; $python = Find-Python }
    $bin = Join-Path $env:USERPROFILE '.local\bin'
    if ($python) {
        $pyExe = $python[0]
        $pyArgs = @($python | Select-Object -Skip 1)
        Run $pyExe @pyArgs -m pipx --version | Out-Null
        if ($LASTEXITCODE -ne 0) { Run $pyExe @pyArgs -m pip install --user --quiet pipx | Out-Null }
        foreach ($tool in 'subliminal', 'ffsubsync') {
            if (Test-Path (Join-Path $bin "$tool.exe")) { Note "$($tool): already installed"; continue }
            Run $pyExe @pyArgs -m pipx install $tool | Out-Null
            if ($LASTEXITCODE -eq 0) { Note "$($tool): installed" }
            else { Warn "$tool didn't install: run  py -m pipx install $tool  later (b / Alt+b need it)" }
        }
    } else {
        Warn 'No Python (and no winget to get it): b and Alt+b need subliminal and ffsubsync from pipx'
    }
}

# ---- 4. mpv-open.exe ------------------------------------------------------------------------

Say 'Building mpv-open.exe, the launcher'
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
if (-not (Test-Path $csc)) { Die "No C# compiler at $csc - this needs the .NET Framework 4 that comes with Windows 10 and 11." }
$exe = Join-Path $Conf 'mpv-open.exe'
$src = Join-Path $env:TEMP "mpv-open-$Stamp.cs"
(Get-Content (Join-Path $Conf 'windows\mpv-open.cs') -Raw).Replace('@@MPV_EXE@@', $mpv.Replace('"', '""')) |
    Set-Content -Path $src -Encoding UTF8
$log = Run $csc /nologo /target:winexe /platform:anycpu /optimize+ "/out:$exe" `
    "/win32icon:$(Join-Path $Conf 'app\icons\mpv.ico')" /r:System.Core.dll /r:System.Web.Extensions.dll $src
$rc = $LASTEXITCODE
Remove-Item $src -ErrorAction SilentlyContinue
if ($rc -ne 0) { $log | ForEach-Object { Write-Host "    $_" }; Die 'mpv-open.exe did not compile.' }
Note "Built $exe"

# ---- 5. Open with, the folder menu, the Start menu --------------------------------------------

if (-not $NoAssociations) {
    Say "Adding $AppName to Open with"
    Remove-Associations                      # start clean: an older install may list other types
    $classes = 'HKCU:\Software\Classes'
    $open = "`"$exe`" `"%1`""
    $icon = "`"$exe`",0"

    function Set-Default($key, $value) {
        if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
        Set-ItemProperty -Path $key -Name '(default)' -Value $value
    }
    function Set-Value($key, $name, $value) {
        if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
        New-ItemProperty -Path $key -Name $name -Value $value -PropertyType String -Force | Out-Null
    }

    # the file type the entries below point at
    Set-Default "$classes\$ProgId" 'Media file'
    Set-Default "$classes\$ProgId\DefaultIcon" $icon
    Set-Default "$classes\$ProgId\shell\open\command" $open
    # the app, as "Open with" and Default apps list it
    $app = "$classes\Applications\mpv-open.exe"
    Set-Value $app 'FriendlyAppName' $AppName
    Set-Default "$app\DefaultIcon" $icon
    Set-Default "$app\shell\open\command" $open
    # and as a registered application, so it gets a page in Settings > Default apps
    $caps = 'HKCU:\Software\MPVTiger\Capabilities'
    Set-Value $caps 'ApplicationName' $AppName
    Set-Value $caps 'ApplicationDescription' 'mpv, set up as MPV Player: Tiger Version'
    Set-Value $caps 'ApplicationIcon' $icon
    Set-Value 'HKCU:\Software\RegisteredApplications' $AppName 'Software\MPVTiger\Capabilities'
    foreach ($ext in $Types) {
        Set-Value "$classes\$ext\OpenWithProgids" $ProgId ''
        Set-Value "$app\SupportedTypes" $ext ''
        Set-Value "$caps\FileAssociations" $ext $ProgId
    }
    # folders: a menu item rather than a file type, as on a Mac's Open With
    $dir = "$classes\Directory\shell\MPVTiger"
    Set-Default $dir "Play with $AppName"
    Set-Value $dir 'Icon' $icon
    Set-Default "$dir\command" $open
    Send-AssocChanged
    Note "Video, audio and playlist files: $($Types.Count) types"

    $ws = New-Object -ComObject WScript.Shell
    $lnk = $ws.CreateShortcut($Shortcut)
    $lnk.TargetPath = $exe
    $lnk.IconLocation = "$exe,0"
    $lnk.Description = 'MPV Player: Tiger Version'
    $lnk.Save()
    Note 'Start menu: mpv (Tiger Version)'
}

Say 'MPV Player: Tiger Version is installed'
Write-Host @"
    Play a video: right-click it, then Open with > $AppName.
    Make it the default: right-click a video > Open with > Choose another app,
    pick $AppName, tick "Always" - or all types at once in
    Settings > Apps > Default apps > $AppName.
    Folders: right-click one > Play with $AppName (Windows 11: Show more options).
    The Cmd shortcuts in the guide are Ctrl here (Ctrl+Delete, Ctrl+t, ...).
    Every key and feature: $Conf\field-guide.html
    The MPV Remote iPhone app is macOS-only for now, so it is not installed here.
"@
