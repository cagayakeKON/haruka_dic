param(
    [ValidateSet('inspect', 'write', 'read', 'delete')][string]$Action = 'inspect',
    [ValidatePattern('^[a-f0-9]{32}$')][string]$RunId
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$identity = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'haruka-installation.json') -Raw | ConvertFrom-Json
if ($identity.payload_kind -ne 'no-network-identity-probe' -or
    $identity.credential_service -notin @('haruka.dictionary.dev', 'haruka.dictionary') -or
    $identity.application_id -ne $identity.credential_service) {
    throw 'Unexpected identity prototype metadata.'
}
if ($Action -eq 'inspect') {
    $identity | ConvertTo-Json -Depth 4
    exit 0
}
if (-not $RunId) { throw 'A run-owned identifier is required for credential proof operations.' }
# The target can only address this run's synthetic credential, never a user credential.
$target = $identity.credential_service + '/installer-proof/' + $RunId
$marker = $identity.environment + ':synthetic-installer-proof:' + $RunId
Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

public static class HarukaInstallerProofCredential {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct Credential {
        public uint Flags;
        public uint Type;
        public string TargetName;
        public string Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public uint CredentialBlobSize;
        public IntPtr CredentialBlob;
        public uint Persist;
        public uint AttributeCount;
        public IntPtr Attributes;
        public string TargetAlias;
        public string UserName;
    }

    [DllImport("advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredWrite(ref Credential credential, uint flags);
    [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredRead(string target, uint type, uint flags, out IntPtr credential);
    [DllImport("advapi32.dll", EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredDelete(string target, uint type, uint flags);
    [DllImport("advapi32.dll")]
    private static extern void CredFree(IntPtr credential);

    public static string Read(string target) {
        IntPtr pointer;
        if (!CredRead(target, 1, 0, out pointer)) {
            int error = Marshal.GetLastWin32Error();
            if (error == 1168) return null;
            throw new Win32Exception(error);
        }
        try {
            var credential = (Credential)Marshal.PtrToStructure(pointer, typeof(Credential));
            var bytes = new byte[credential.CredentialBlobSize];
            Marshal.Copy(credential.CredentialBlob, bytes, 0, bytes.Length);
            return Encoding.UTF8.GetString(bytes);
        } finally { CredFree(pointer); }
    }

    public static void WriteNew(string target, string marker) {
        if (Read(target) != null) throw new InvalidOperationException("Synthetic target already exists.");
        var bytes = Encoding.UTF8.GetBytes(marker);
        var pointer = Marshal.AllocCoTaskMem(bytes.Length);
        try {
            Marshal.Copy(bytes, 0, pointer, bytes.Length);
            var credential = new Credential {
                Type = 1, TargetName = target, UserName = "haruka-installer-proof",
                Comment = "Synthetic installation identity test; no user credentials",
                CredentialBlobSize = (uint)bytes.Length, CredentialBlob = pointer, Persist = 2
            };
            if (!CredWrite(ref credential, 0)) throw new Win32Exception(Marshal.GetLastWin32Error());
        } finally { Marshal.FreeCoTaskMem(pointer); }
    }

    public static void DeleteOwned(string target, string marker) {
        var actual = Read(target);
        if (actual == null) return;
        if (actual != marker) throw new InvalidOperationException("Synthetic credential ownership differs.");
        if (!CredDelete(target, 1, 0)) throw new Win32Exception(Marshal.GetLastWin32Error());
    }
}
'@
switch ($Action) {
    'write' { [HarukaInstallerProofCredential]::WriteNew($target, $marker) }
    'read' {
        if ([HarukaInstallerProofCredential]::Read($target) -ne $marker) {
            throw 'Synthetic credential was missing or crossed environment scope.'
        }
    }
    'delete' {
        [HarukaInstallerProofCredential]::DeleteOwned($target, $marker)
        if ($null -ne [HarukaInstallerProofCredential]::Read($target)) {
            throw 'Synthetic credential cleanup did not complete.'
        }
    }
}
@{ action = $Action; environment = $identity.environment; credential_service = $identity.credential_service; passed = $true } | ConvertTo-Json
