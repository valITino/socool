# PSScriptAnalyzerSettings.psd1 — repo-wide static-analysis policy.
#
# Loaded by .github/workflows/ci.yml via -Settings. CI fails on any
# Error-severity finding outside the exclude list. Warnings are
# reported but non-fatal so contributors aren't blocked by stylistic
# issues; tighten this in a follow-up PR if/when the codebase is
# warning-clean.
#
# When excluding a rule, leave a one-line rationale comment.
@{
    Severity     = @('Error')

    ExcludeRules = @(
        # SOCool's user-facing CLI prints status to the terminal via
        # Write-Host (parity with `printf` on the bash side). We never
        # use the pipeline output stream for UI text.
        'PSAvoidUsingWriteHost',

        # PowerShell 7+ files default to UTF-8 without BOM, which is
        # the modern cross-platform norm. Forcing a BOM would break
        # parity with the bash sources committed without one.
        'PSUseBOMForUnicodeEncodedFile',

        # Some helper functions intentionally use plural nouns
        # ('Get-Deps' returns a collection). Ignored at the repo level
        # to avoid renaming public-ish surface late in the cycle.
        'PSUseSingularNouns',

        # Generating a fresh random password and converting it to a
        # SecureString for `Set-LocalUser -Password` is justified —
        # the plaintext is the just-generated CSPRNG output, never a
        # static credential. Audited use lives in
        # packer/windows-victim/scripts/rotate-credentials.ps1.
        'PSAvoidUsingConvertToSecureStringWithPlainText'
    )
}
