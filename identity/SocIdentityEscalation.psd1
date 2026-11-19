@{
    RootModule        = 'SocIdentityEscalation.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '11111111-2222-3333-4444-555555550005'
    Author            = 'ShahradGH'
    CompanyName       = 'Independent Architecture'
    Copyright         = '(c) ShahradGH. MIT License.'
    Description       = 'Microsoft Graph v2.x SOC responder roster resolution, Entra ID Identity Protection risky-user correlation, and Teams fraud escalation.'
    PowerShellVersion = '7.4'
    FunctionsToExport = @(
        'Get-SocOnCallResponderRoster',
        'Test-MerchantAdminSignInRisk',
        'Invoke-FraudCaseTeamsThread'
    )
}
