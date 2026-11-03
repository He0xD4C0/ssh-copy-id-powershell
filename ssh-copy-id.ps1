<#
.SYNOPSIS
Installs one SSH public key into a remote account.
.DESCRIPTION
Unix targets require a POSIX shell. For Windows OpenSSH, specify
-RemotePlatform Windows; the standard per-user authorized_keys location is used.
An existing login method is required. Success means the key was written,
not that the server accepts it for authentication.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateNotNullOrEmpty()][string]$User,
    [Parameter(Mandatory, Position = 1)]
    [ValidateNotNullOrEmpty()][string]$RemoteHost,
    [string]$IdentityFile,
    [ValidateRange(1, 65535)][int]$Port = 22,
    [ValidateSet('Unix', 'Windows')][string]$RemotePlatform = 'Unix'
)

$ErrorActionPreference = 'Stop'
try {
    $ssh = (Get-Command ssh.exe -CommandType Application -ErrorAction Stop).Source
    $keygen = (Get-Command ssh-keygen.exe -CommandType Application -ErrorAction Stop).Source
    if ([string]::IsNullOrWhiteSpace($User) -or
        [string]::IsNullOrWhiteSpace($RemoteHost) -or $RemoteHost.StartsWith('-')) {
        throw 'Invalid username or remote host.'
    }
    if (-not $IdentityFile) {
        foreach ($name in 'id_ed25519.pub', 'id_ecdsa.pub', 'id_rsa.pub') {
            $candidate = Join-Path $HOME ".ssh/$name"
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                $IdentityFile = $candidate
                break
            }
        }
    }
    if (-not $IdentityFile -or -not (Test-Path -LiteralPath $IdentityFile -PathType Leaf)) {
        throw 'Public key file not found. Use -IdentityFile to specify one.'
    }
    $key = (Get-Content -LiteralPath $IdentityFile -Raw -ErrorAction Stop).Trim()
    if ($key -notmatch '\A(?:ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(?:256|384|521)|sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-nistp256@openssh\.com) [A-Za-z0-9+/]+={0,2}(?: [^\r\n]*)?\z') {
        throw 'Expected exactly one public key, without authorized_keys options.'
    }
    # Validate the exact normalized content that will be sent, not a second read.
    $validationFile = [IO.Path]::GetTempFileName()
    try {
        [IO.File]::WriteAllText($validationFile, $key + "`n", [Text.UTF8Encoding]::new($false))
        & $keygen -lf $validationFile | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Invalid public key.' }
    } finally {
        Remove-Item -LiteralPath $validationFile -Force
    }
    # Only the key type and blob are needed; comments are not transmitted.
    $parts = $key -split ' ', 3
    $key = $parts[0] + ' ' + $parts[1]
    if ($RemotePlatform -eq 'Windows') {
        $body = @'
$ErrorActionPreference = 'Stop'
try {
    $key = [Console]::In.ReadToEnd().Trim()
    $dir = Join-Path $HOME '.ssh'
    $path = Join-Path $dir 'authorized_keys'
    [IO.Directory]::CreateDirectory($dir) | Out-Null
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    & icacls.exe $dir /inheritance:r /grant:r "*${sid}:(OI)(CI)F" '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Cannot secure .ssh directory.' }
    if (-not [IO.File]::Exists($path)) { [IO.File]::WriteAllText($path, '') }
    & icacls.exe $path /inheritance:r /grant:r "*${sid}:F" '*S-1-5-18:F' '*S-1-5-32-544:F' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Cannot secure authorized_keys.' }
    $text = [IO.File]::ReadAllText($path)
    $found = @($text -split '\r?\n' | Where-Object { $_ -eq $key -or $_.StartsWith($key + ' ') }).Count -gt 0
    if (-not $found) {
        $prefix = if ($text.Length -gt 0 -and -not $text.EndsWith("`n")) { "`n" } else { '' }
        [IO.File]::AppendAllText($path, $prefix + $key + "`n", [Text.UTF8Encoding]::new($false))
    }
} catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }
'@
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($body))
        $remoteCommand = "powershell.exe -NoProfile -NonInteractive -EncodedCommand $encoded"
    } else {
        $remoteCommand = @'
set -eu
umask 077
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
file="$HOME/.ssh/authorized_keys"
touch "$file"
chmod 600 "$file"
IFS= read -r key
key=$(printf '%s' "$key" | tr -d '\r')
if ! awk -v key="$key" '$0 == key || index($0, key " ") == 1 { found=1 } END { exit !found }' "$file"; then
    if [ -s "$file" ] && [ "$(tail -c 1 "$file" | wc -l)" -eq 0 ]; then
        printf '\n' >> "$file"
    fi
    printf '%s\n' "$key" >> "$file"
fi
'@
        $remoteCommand = $remoteCommand.Replace("`r", '')
    }
    # Windows PowerShell uses legacy native argument quoting.
    if ($PSVersionTable.PSVersion.Major -le 5) {
        $remoteCommand = $remoteCommand.Replace('"', '\"')
    }
    $sshArgs = @('-T', '-p', "$Port", '-l', $User, $RemoteHost, $remoteCommand)
    $key | & $ssh @sshArgs
    $code = $LASTEXITCODE
    if ($code -ne 0) { exit $code }
    Write-Host "Public key written (or already present) for $User@$RemoteHost."
} catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
}
