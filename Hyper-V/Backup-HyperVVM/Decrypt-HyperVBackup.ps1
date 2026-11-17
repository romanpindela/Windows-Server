<#
================================================================================
  Script Name : Decrypt-HyperVBackup.ps1
  Author      : Roman Pindela
  Contact     : roman.pindela@gmail.com
  Version     : 1.1.0
  Release Date: 2026-11-17
  License     : MIT
  Repository  : https://github.com/romanpindela/Windows-Server

  DESCRIPTION:
    100% native Microsoft (.NET) decryption and extraction utility for
    AES-256-CBC + HMAC-SHA256 encrypted Hyper-V VM backup archives (.zip.aes)
    created by Backup-HyperVVM.ps1. Works on Windows PowerShell 5.1 and
    PowerShell 7+ without any third-party tools.
================================================================================
#>

<#
.SYNOPSIS
    Decrypts and optionally extracts an AES-256 encrypted Hyper-V backup
    archive (.zip.aes) created by Backup-HyperVVM.ps1.

.PARAMETER ArchivePath
    Path to the .zip.aes backup file.

.PARAMETER DestinationPath
    Optional directory where the decrypted ZIP contents will be extracted.
    If omitted, only the decrypted .zip file is written next to the archive.

.PARAMETER ZipPassword
    Decryption password as a [SecureString]. Prompts securely if omitted.

.PARAMETER KeepDecryptedZip
    Switch parameter. Keeps the intermediate .zip file when -DestinationPath
    is specified.

.PARAMETER Help
    Displays help and exits.

.EXAMPLE
    .\Decrypt-HyperVBackup.ps1 -ArchivePath "C:\DANE\Backup\DC01_20261117-220000.zip.aes" -DestinationPath "C:\Restore\DC01"
#>

[CmdletBinding()]
param (
    [Parameter(Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$ArchivePath,

    [Parameter(Position = 1)]
    [string]$DestinationPath,

    [Parameter()]
    [Alias('Password')]
    [SecureString]$ZipPassword,

    [Parameter()]
    [switch]$KeepDecryptedZip,

    [Parameter()]
    [Alias('h')]
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Help -or $PSBoundParameters.Count -eq 0) {
    Write-Host ''
    Write-Host 'Decrypt-HyperVBackup.ps1 (v1.1.0) - Native .NET AES-256 Backup Decryptor' -ForegroundColor Cyan
    Write-Host 'Usage:' -ForegroundColor Yellow
    Write-Host '  .\Decrypt-HyperVBackup.ps1 -ArchivePath <file.zip.aes> [-DestinationPath <folder>] [-ZipPassword <SecureString>] [-KeepDecryptedZip]'
    Write-Host ''
    exit 0
}

if (-not (Test-Path -Path $ArchivePath -PathType Leaf)) {
    throw "Encrypted archive not found: $ArchivePath"
}

if ($null -eq $ZipPassword) {
    $ZipPassword = Read-Host -Prompt 'Enter decryption password' -AsSecureString
}

Add-Type -AssemblyName System.IO.Compression.FileSystem

$magicHeader = [System.Text.Encoding]::ASCII.GetBytes('HYPVAES1')
$decryptedZipPath = if ($ArchivePath -match '\.aes$') {
    $ArchivePath -replace '\.aes$', ''
}
else {
    "$ArchivePath.zip"
}

$bstr = [System.IntPtr]::Zero
$passwordBytes = $null
$inStream = $null
$outStream = $null
$cryptoStream = $null
$aes = $null
$hmac = $null
$kdf = $null

try {
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ZipPassword)
    $plainPwd = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    $passwordBytes = [System.Text.Encoding]::UTF8.GetBytes($plainPwd)
    $plainPwd = $null

    $inStream = [System.IO.File]::OpenRead((Resolve-Path -Path $ArchivePath).Path)
    if ($inStream.Length -lt (8 + 32 + 16 + 32)) {
        throw 'Archive file is too small or corrupted.'
    }

    $headerBuf = New-Object byte[] 8
    [void]$inStream.Read($headerBuf, 0, 8)
    for ($i = 0; $i -lt 8; $i++) {
        if ($headerBuf[$i] -ne $magicHeader[$i]) {
            throw 'Invalid archive header. Expected HYPVAES1 format.'
        }
    }

    $salt = New-Object byte[] 32
    $iv = New-Object byte[] 16
    [void]$inStream.Read($salt, 0, 32)
    [void]$inStream.Read($iv, 0, 16)

    $kdf = [System.Security.Cryptography.Rfc2898DeriveBytes]::new($passwordBytes, $salt, 100000)
    $aesKey = $kdf.GetBytes(32)
    $hmacKey = $kdf.GetBytes(32)

    $ciphertextLength = $inStream.Length - 8 - 32 - 16 - 32
    $storedHmac = New-Object byte[] 32
    $inStream.Position = $inStream.Length - 32
    [void]$inStream.Read($storedHmac, 0, 32)

    # Verify HMAC-SHA256 before decrypting
    Write-Host '[INFO] Verifying HMAC-SHA256 integrity and password...' -ForegroundColor Cyan
    $hmac = [System.Security.Cryptography.HMACSHA256]::new($hmacKey)
    $inStream.Position = 0
    $remainingToHash = $inStream.Length - 32
    $buffer = New-Object byte[] (1024 * 1024)
    while ($remainingToHash -gt 0) {
        $toRead = [int][Math]::Min($buffer.Length, $remainingToHash)
        $read = $inStream.Read($buffer, 0, $toRead)
        if ($read -le 0) { break }
        [void]$hmac.TransformBlock($buffer, 0, $read, $buffer, 0)
        $remainingToHash -= $read
    }
    [void]$hmac.TransformFinalBlock([byte[]]@(), 0, 0)
    $computedHmac = $hmac.Hash

    $hmacMatch = $true
    for ($i = 0; $i -lt 32; $i++) {
        if ($computedHmac[$i] -ne $storedHmac[$i]) {
            $hmacMatch = $false
        }
    }
    if (-not $hmacMatch) {
        throw 'HMAC verification failed: wrong password or corrupted archive.'
    }

    # Decrypt ciphertext stream to .zip
    Write-Host "[INFO] Decrypting archive to '$decryptedZipPath'..." -ForegroundColor Cyan
    $inStream.Position = 8 + 32 + 16
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.KeySize = 256
    $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
    $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
    $aes.Key = $aesKey
    $aes.IV = $iv

    $outStream = [System.IO.File]::Create($decryptedZipPath)
    $decryptor = $aes.CreateDecryptor()
    $cryptoStream = [System.Security.Cryptography.CryptoStream]::new($outStream, $decryptor, [System.Security.Cryptography.CryptoStreamMode]::Write)

    $remainingCipher = $ciphertextLength
    while ($remainingCipher -gt 0) {
        $toRead = [int][Math]::Min($buffer.Length, $remainingCipher)
        $read = $inStream.Read($buffer, 0, $toRead)
        if ($read -le 0) { break }
        $cryptoStream.Write($buffer, 0, $read)
        $remainingCipher -= $read
    }
    $cryptoStream.FlushFinalBlock()
    $cryptoStream.Dispose()
    $cryptoStream = $null
    $outStream.Dispose()
    $outStream = $null

    Write-Host "[SUCCESS] Decrypted ZIP created: $decryptedZipPath" -ForegroundColor Green

    if (-not [string]::IsNullOrWhiteSpace($DestinationPath)) {
        if (-not (Test-Path -Path $DestinationPath)) {
            New-Item -Path $DestinationPath -ItemType Directory -Force | Out-Null
        }
        Write-Host "[INFO] Extracting ZIP to '$DestinationPath'..." -ForegroundColor Cyan
        [System.IO.Compression.ZipFile]::ExtractToDirectory($decryptedZipPath, $DestinationPath)
        Write-Host "[SUCCESS] Extraction completed: $DestinationPath" -ForegroundColor Green

        if (-not $KeepDecryptedZip -and (Test-Path -Path $decryptedZipPath)) {
            Remove-Item -Path $decryptedZipPath -Force
        }
    }
}
finally {
    if ($null -ne $cryptoStream) { $cryptoStream.Dispose() }
    if ($null -ne $outStream) { $outStream.Dispose() }
    if ($null -ne $inStream) { $inStream.Dispose() }
    if ($null -ne $aes) { $aes.Dispose() }
    if ($null -ne $hmac) { $hmac.Dispose() }
    if ($null -ne $kdf) { $kdf.Dispose() }
    if ($null -ne $passwordBytes) { [Array]::Clear($passwordBytes, 0, $passwordBytes.Length) }
    if ($bstr -ne [System.IntPtr]::Zero) { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}
